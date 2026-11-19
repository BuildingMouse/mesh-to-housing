from typing import Annotated, Union

from pydantic import Field

from .base import CandidateScorer, IncrementalLoss, Loss, LossConfig, LossSession, implements
from .combined import CombinedLoss, CombinedLossConfig, LossTerm
from .sessions import FullEvaluationSession
from .voxel import (
    ChamferDistanceConfig, ChamferDistanceLoss, HausdorffDistanceConfig, HausdorffDistanceLoss,
    ExcessSurfaceConfig, ExcessSurfaceLoss, OutsideVolumeConfig, OutsideVolumeLoss, SurfaceFScoreConfig,
    SurfaceFScoreLoss, SurfacePrecisionConfig, SurfacePrecisionLoss, SurfaceRecallConfig, SurfaceRecallLoss,
    UncoveredSurfaceConfig, UncoveredSurfaceLoss, UncoveredVolumeConfig,
    UncoveredVolumeLoss,
)

LossConfigs = Annotated[
    Union[
        ChamferDistanceConfig, CombinedLossConfig, ExcessSurfaceConfig, HausdorffDistanceConfig, OutsideVolumeConfig,
        SurfaceFScoreConfig, SurfacePrecisionConfig, SurfaceRecallConfig, UncoveredSurfaceConfig, UncoveredVolumeConfig,
    ],
    Field(discriminator="type"),
]
LossTerm.model_rebuild()
CombinedLossConfig.model_rebuild()

__all__ = [
    "CandidateScorer", "CombinedLoss", "CombinedLossConfig", "FullEvaluationSession", "IncrementalLoss", "Loss",
    "LossConfig", "LossConfigs", "LossSession", "LossTerm",
    "ChamferDistanceConfig", "ChamferDistanceLoss", "ExcessSurfaceConfig", "ExcessSurfaceLoss",
    "HausdorffDistanceConfig", "HausdorffDistanceLoss",
    "OutsideVolumeConfig", "OutsideVolumeLoss",
    "SurfaceFScoreConfig", "SurfaceFScoreLoss", "SurfacePrecisionConfig", "SurfacePrecisionLoss",
    "SurfaceRecallConfig", "SurfaceRecallLoss",
    "UncoveredSurfaceConfig", "UncoveredSurfaceLoss",
    "UncoveredVolumeConfig", "UncoveredVolumeLoss", "implements",
]
