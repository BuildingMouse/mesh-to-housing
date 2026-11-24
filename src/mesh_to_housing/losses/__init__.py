from typing import Annotated, Union

from pydantic import Field

from .base import CandidateScorer, IncrementalLoss, Loss, LossConfig, LossSession, implements
from .combined import CombinedLoss, CombinedLossConfig, LossTerm
from .sessions import FullEvaluationSession
from .voxel import (
    ChamferDistanceConfig, ChamferDistanceLoss, ExcessRoughnessConfig, ExcessRoughnessLoss, ExcessSurfaceConfig,
    ExcessSurfaceLoss, HausdorffDistanceConfig, HausdorffDistanceLoss, OutsideVolumeConfig, OutsideVolumeLoss,
    SurfaceFScoreConfig, SurfaceFScoreLoss, SurfacePrecisionConfig, SurfacePrecisionLoss, SurfaceRecallConfig,
    SurfaceRecallLoss, UncoveredSurfaceConfig, UncoveredSurfaceLoss, UncoveredVolumeConfig, UncoveredVolumeLoss,
)

LossConfigs = Annotated[
    Union[
        ChamferDistanceConfig, CombinedLossConfig, ExcessRoughnessConfig, ExcessSurfaceConfig, HausdorffDistanceConfig,
        OutsideVolumeConfig, SurfaceFScoreConfig, SurfacePrecisionConfig, SurfaceRecallConfig, UncoveredSurfaceConfig,
        UncoveredVolumeConfig,
    ],
    Field(discriminator="type"),
]
LossTerm.model_rebuild()
CombinedLossConfig.model_rebuild()

__all__ = [
    "CandidateScorer", "ChamferDistanceConfig", "ChamferDistanceLoss", "CombinedLoss", "CombinedLossConfig",
    "ExcessRoughnessConfig", "ExcessRoughnessLoss", "ExcessSurfaceConfig", "ExcessSurfaceLoss", "FullEvaluationSession",
    "HausdorffDistanceConfig", "HausdorffDistanceLoss", "IncrementalLoss", "Loss", "LossConfig", "LossConfigs",
    "LossSession", "LossTerm", "OutsideVolumeConfig", "OutsideVolumeLoss", "SurfaceFScoreConfig", "SurfaceFScoreLoss",
    "SurfacePrecisionConfig", "SurfacePrecisionLoss", "SurfaceRecallConfig", "SurfaceRecallLoss",
    "UncoveredSurfaceConfig", "UncoveredSurfaceLoss", "UncoveredVolumeConfig", "UncoveredVolumeLoss", "implements",
]
