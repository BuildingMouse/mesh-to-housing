from pathlib import Path
from typing import Optional, Sequence, Union

import numpy as np
from pydantic import model_validator

from ..utils.config import Config
from ..utils.values import NonNegativeFloat
from ..construction import Construction
from ..losses import LossConfigs
from ..losses.base import Loss
from ..task import FittingTask
from .proposals import ProposalConfigs
from .report import Report
from .stage import StepConfigs
from .state import FitState, Scope
from .steps import Step


class FittingPipeline(Config):
    """A whole fit in one config: named losses and proposal sources, the steps that use them, and the metrics
    that report on the result. Every action must run inside a stage that sets minimize.
    """

    losses: dict[str, LossConfigs]
    proposals: dict[str, ProposalConfigs] = {}
    min_gain: NonNegativeFloat = 1e-12
    steps: tuple[StepConfigs, ...] = ()
    metrics: dict[str, LossConfigs] = {}

    @model_validator(mode="after")
    def _check(self):
        self._check_steps(self.steps, "steps", loss_set=False)
        return self

    def _check_steps(self, steps: Sequence[Step], path: str, loss_set: bool) -> None:
        for index, step in enumerate(steps):
            label = getattr(step, "name", None)
            where = f"{path}[{index}]" if label is None else f"{path}[{index}] ({label})"
            for kind, names, known in (("loss", step.losses_used(), self.losses),
                                       ("proposals", step.proposals_used(), self.proposals)):
                for name in names:
                    if name not in known:
                        raise ValueError(f"{where}: no {kind} named {name!r}; the pipeline has "
                                         f"{', '.join(known) or 'none'}")
            if step.needs_loss() and not loss_set:
                raise ValueError(f"{where}: {type(step).__name__} runs outside any stage that sets minimize")
            self._check_steps(step.children(), f"{where}.steps", loss_set or bool(step.losses_used()))

    def fit(self, task: FittingTask, *, seed: Optional[int] = None) -> Construction:
        """Build a new construction for the task."""
        return self.refit(task, Construction(), seed=seed)

    def refit(self, task: FittingTask, construction: Construction, *, seed: Optional[int] = None) -> Construction:
        """Continue from an existing construction."""
        if not task.max_items:
            return Construction()
        state = FitState(task, np.random.default_rng(seed), self.losses, self.proposals, Scope(), self.min_gain,
                         tuple(construction))
        for step in self.steps:
            step.run(state)
        result = state.construction()
        task.validate(result)
        return result

    def evaluate(self, task: FittingTask, construction: Construction) -> Report:
        """Score the construction on each of the pipeline's metrics."""
        metrics = {name: Loss.from_config(config)(task.target, construction) for name, config in self.metrics.items()}
        return Report(metrics, len(construction))

    @classmethod
    def load(cls, path: Union[str, Path]) -> "FittingPipeline":
        """A pipeline from a YAML file."""
        return cls.from_yaml(Path(path).read_text())

    def save(self, path: Union[str, Path], *, full: bool = False) -> None:
        """Write the pipeline to a YAML file."""
        Path(path).write_text(self.to_yaml(full=full))
