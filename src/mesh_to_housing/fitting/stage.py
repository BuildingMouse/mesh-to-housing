"""Steps that contain other steps: stages and repeats."""
from dataclasses import replace
from typing import Annotated, Any, Literal, Optional, Union

from pydantic import Discriminator, Tag, model_serializer, model_validator

from ..utils.config import Config
from ..utils.values import Fraction, PositiveInt
from .selection import SelectionConfigs
from .state import FitState, Scope
from .steps import Fill, Step


class CandidateSettings(Config):
    """Fixed sources propose once, when the stage starts; 
    refreshed sources propose again as the construction grows.
    """

    fixed: Optional[tuple[str, ...]] = None
    refreshed: Optional[tuple[str, ...]] = None
    refresh_every: Optional[PositiveInt] = None

    def proposals_used(self) -> tuple[str, ...]:
        return (*(self.fixed or ()), *(self.refreshed or ()))

    def apply_to(self, state: FitState, scope: Scope) -> Scope:
        """The scope with these settings applied, except the fixed pools, which the stage proposes itself."""
        scope = replace(
            scope,
            refreshed=scope.refreshed if self.refreshed is None else tuple(map(state.proposals_named, self.refreshed)),
            refresh_every=scope.refresh_every if self.refresh_every is None else self.refresh_every,
        )
        return scope


class ItemSettings(Config):
    """How many items a stage may add, as a share of the task's item budget."""

    budget: Optional[Fraction] = None

    def apply_to(self, state: FitState, scope: Scope) -> Scope:
        if self.budget is not None:
            added = int(round(self.budget * state.task.max_items))
            scope = replace(scope, max_items=len(state.placements) + added)
        return scope


class Stage(Config, Step):
    """Runs its steps with its own settings, and the enclosing stage's for anything it leaves out."""

    type: Literal["stage"] = "stage"
    name: Optional[str] = None
    minimize: Optional[str] = None
    select: Optional[SelectionConfigs] = None
    candidates: Optional[CandidateSettings] = None
    items: Optional[ItemSettings] = None
    steps: tuple["StepConfigs", ...] = ()

    @model_validator(mode="before")
    @classmethod
    def _name_from_label(cls, data: Any) -> Any:
        if isinstance(data, dict) and "stage" in data:
            data = dict(data)
            data["name"] = data.pop("stage")
            data.setdefault("type", "stage")
        return data

    @model_serializer(mode="wrap")
    def _serialize(self, handler):
        data = {name: value for name, value in handler(self).items() if name not in ("type", "name")}
        return {"stage": self.name, **data} if self.name is not None else {"type": "stage", **data}

    def children(self):
        return self.steps

    def losses_used(self):
        return () if self.minimize is None else (self.minimize,)

    def proposals_used(self):
        return () if self.candidates is None else self.candidates.proposals_used()


    def needs_loss(self):
        return False

    def run(self, state):
        outer = state.scope
        scope = replace(
            outer,
            loss=outer.loss if self.minimize is None else self.minimize,
            selection=outer.selection if self.select is None else self.select,
        )
        if self.items is not None:
            scope = self.items.apply_to(state, scope)
        if self.candidates is not None:
            scope = self.candidates.apply_to(state, scope)
        state.use(scope)
        fixed = None if self.candidates is None else self.candidates.fixed
        if fixed is not None:
            pools = tuple(state.propose(state.proposals_named(name)) for name in fixed)
            state.use(replace(state.scope, pools=pools))
        try:
            for step in self.steps:
                step.run(state)
        finally:
            state.use(outer)


class Repeat(Config, Step):
    """Runs its steps the given number of times."""

    type: Literal["repeat"] = "repeat"
    times: PositiveInt
    steps: tuple["StepConfigs", ...] = ()

    def children(self):
        return self.steps

    def needs_loss(self):
        return False

    def run(self, state):
        for _ in range(self.times):
            for step in self.steps:
                step.run(state)


def _kind(value: Any) -> Optional[str]:
    if isinstance(value, dict):
        return value.get("type", "stage" if "stage" in value else None)
    return getattr(value, "type", None)


StepConfigs = Annotated[
    Union[Annotated[Fill, Tag("fill")], Annotated[Stage, Tag("stage")], Annotated[Repeat, Tag("repeat")]],
    Discriminator(_kind),
]
Stage.model_rebuild()
Repeat.model_rebuild()
