from dataclasses import dataclass
from types import MappingProxyType
from typing import Iterator, Mapping


@dataclass(frozen=True)
class Report:
    """How a construction scores on a pipeline's metrics. Lower is better."""

    metrics: Mapping[str, float]
    items: int

    def __post_init__(self):
        metrics = {name: float(value) for name, value in self.metrics.items()}
        object.__setattr__(self, "metrics", MappingProxyType(metrics))

    def __getitem__(self, name: str) -> float:
        return self.metrics[name]

    def __iter__(self) -> Iterator[str]:
        return iter(self.metrics)

    def to_dict(self) -> dict:
        return {"items": self.items, "metrics": dict(self.metrics)}

    def __str__(self) -> str:
        width = max((len(name) for name in self.metrics), default=0)
        lines = [f"{'items':<{width}}  {self.items}"]
        lines += [f"{name:<{width}}  {value:.4g}" for name, value in self.metrics.items()]
        return "\n".join(lines)
