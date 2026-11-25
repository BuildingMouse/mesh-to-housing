"""F-score, Chamfer, Hausdorff and excess roughness between the outer surfaces of the target and the construction."""
import numpy as np
import pytest
import trimesh
from pydantic import ValidationError

from mesh_to_housing import (
    ChamferDistanceConfig, ConfigError, Construction, Cuboid, ExcessRoughnessConfig, FittingPipeline,
    HausdorffDistanceConfig, Loss, Placement, SurfaceFScoreConfig, VoxelGridConfig,
)

GRID = VoxelGridConfig(resolution=16)
METRICS = (SurfaceFScoreConfig, ChamferDistanceConfig, HausdorffDistanceConfig)
DIRECTIONS = ("both", "to_target", "to_construction")


def target(scale=1.0):
    return trimesh.creation.box(extents=(2.0 * scale, scale, scale))


def boxes(*parts, scale=1.0):
    """A construction of boxes given as (size, center) pairs."""
    return Construction(tuple(Placement(Cuboid(f"box{index}", tuple(np.multiply(size, scale))),
                                        np.multiply(center, scale), np.eye(3))
                              for index, (size, center) in enumerate(parts)))


def loss(config_class, **settings):
    return Loss.from_config(config_class(grid=GRID, **settings))


@pytest.mark.parametrize("direction", DIRECTIONS)
@pytest.mark.parametrize("config_class", METRICS)
def test_an_empty_construction_scores_one(config_class, direction):
    assert loss(config_class, direction=direction)(target(), Construction()) == 1.0


@pytest.mark.parametrize("direction", DIRECTIONS)
@pytest.mark.parametrize("config_class", METRICS)
def test_an_exact_match_scores_zero(config_class, direction):
    exact = boxes(((2.0, 1.0, 1.0), (0.0, 0.0, 0.0)))
    assert loss(config_class, direction=direction)(target(), exact) == pytest.approx(0.0, abs=1e-9)


def test_a_box_shifted_by_half_its_length():
    shifted = boxes(((2.0, 1.0, 1.0), (1.0, 0.0, 0.0)))
    precision, recall, fscore = (loss(SurfaceFScoreConfig, direction=direction)(target(), shifted)
                                 for direction in ("to_target", "to_construction", "both"))
    assert precision == pytest.approx(recall)
    assert fscore == pytest.approx(precision)
    assert 0.0 < fscore < 1.0
    # The far end is a whole box length away, and distances are shares of the longest side.
    assert loss(HausdorffDistanceConfig)(target(), shifted) == pytest.approx(0.5)


def test_directions_measure_each_side():
    half = boxes(((1.0, 1.0, 1.0), (-0.5, 0.0, 0.0)))
    chamfer = {direction: loss(ChamferDistanceConfig, direction=direction)(target(), half) for direction in DIRECTIONS}
    hausdorff = {direction: loss(HausdorffDistanceConfig, direction=direction)(target(), half)
                 for direction in DIRECTIONS}
    # The half box lies inside the target, so the missing half shows only from the target's side.
    assert chamfer["to_target"] < chamfer["to_construction"]
    assert chamfer["both"] == pytest.approx((chamfer["to_target"] + chamfer["to_construction"]) / 2)
    assert hausdorff["to_construction"] == pytest.approx(0.5)
    assert hausdorff["both"] == max(hausdorff["to_target"], hausdorff["to_construction"])


def test_target_surface_buried_inside_an_item_counts_as_missed():
    around = boxes(((3.0, 2.0, 2.0), (0.0, 0.0, 0.0)))
    assert loss(SurfaceFScoreConfig, direction="to_construction")(target(), around) == 1.0
    assert loss(SurfaceFScoreConfig, direction="to_target")(target(), around) == 1.0


def test_space_enclosed_inside_the_construction_counts_as_filled():
    # A hollow shell of six slabs has the same outer surface as the solid box.
    wall = 0.25
    shell = boxes(((2.0, 1.0, wall), (0.0, 0.0, 0.5 - wall / 2)), ((2.0, 1.0, wall), (0.0, 0.0, -0.5 + wall / 2)),
                  ((2.0, wall, 1.0), (0.0, 0.5 - wall / 2, 0.0)), ((2.0, wall, 1.0), (0.0, -0.5 + wall / 2, 0.0)),
                  ((wall, 1.0, 1.0), (1.0 - wall / 2, 0.0, 0.0)), ((wall, 1.0, 1.0), (-1.0 + wall / 2, 0.0, 0.0)))
    for config_class in METRICS:
        assert loss(config_class)(target(), shell) == pytest.approx(0.0, abs=1e-9)


@pytest.mark.parametrize("config_class", METRICS)
def test_values_keep_their_meaning_at_any_target_size(config_class):
    def value(scale):
        return loss(config_class)(target(scale), boxes(((1.0, 1.0, 1.0), (-0.5, 0.0, 0.0)),
                                                       ((0.6, 0.6, 0.6), (0.9, 0.4, 0.4)), scale=scale))

    assert value(3.0) == pytest.approx(value(1.0))


def test_direction_must_be_one_of_the_three():
    with pytest.raises(ValidationError):
        ChamferDistanceConfig(direction="sideways")
    with pytest.raises(ConfigError, match="direction"):
        FittingPipeline.from_yaml("losses: {d: {type: hausdorff_distance, direction: sideways}}\n")


def test_metrics_read_from_yaml():
    pipeline = FittingPipeline.from_yaml(
        "losses: {fscore: {type: surface_fscore, surface_tolerance: 0.05}}\n"
        "metrics:\n"
        "  recall: {type: surface_fscore, direction: to_construction}\n"
        "  accuracy: {type: chamfer_distance, direction: to_target}\n")
    assert pipeline.losses["fscore"] == SurfaceFScoreConfig(surface_tolerance=0.05)
    assert pipeline.metrics["accuracy"] == ChamferDistanceConfig(direction="to_target")
    assert FittingPipeline.from_yaml(pipeline.to_yaml()) == pipeline


# Roughness is measured over two cells, so its tests need parts a few cells across.
ROUGH_GRID = VoxelGridConfig(resolution=32)
BUMP = ((0.25, 0.25, 0.25), (0.0, 0.0, 0.625))
RIDGE = ((1.5, 0.25, 0.25), (0.0, 0.0, 0.625))


def ridged(scale=1.0):
    """The target box with a ridge along the middle of its top face."""
    size, center = RIDGE
    ridge = trimesh.creation.box(extents=np.multiply(size, scale))
    ridge.apply_translation(np.multiply(center, scale))
    return trimesh.util.concatenate([target(scale), ridge])


def excess_roughness(target_mesh, construction):
    return Loss.from_config(ExcessRoughnessConfig(grid=ROUGH_GRID))(target_mesh, construction)


def test_excess_roughness_is_near_zero_without_extra_bumps():
    whole = ((2.0, 1.0, 1.0), (0.0, 0.0, 0.0))
    bumped = excess_roughness(target(), boxes(whole, BUMP))
    assert excess_roughness(target(), Construction()) == 0.0
    assert excess_roughness(target(), boxes(whole)) < bumped / 100
    assert excess_roughness(ridged(), boxes(whole, RIDGE)) < bumped / 10
    # Smoother than the target costs nothing: flattened detail is for uncovered surface.
    assert excess_roughness(ridged(), boxes(whole)) < bumped / 10


def test_excess_roughness_charges_bumps_the_target_does_not_have():
    whole = ((2.0, 1.0, 1.0), (0.0, 0.0, 0.0))
    assert excess_roughness(target(), boxes(whole, BUMP)) > 0.005
    assert excess_roughness(target(), boxes(whole, RIDGE)) > 5 * excess_roughness(ridged(), boxes(whole, RIDGE))


def test_excess_roughness_keeps_its_meaning_at_any_target_size():
    def value(scale):
        return excess_roughness(target(scale), boxes(((2.0, 1.0, 1.0), (0.0, 0.0, 0.0)), BUMP, scale=scale))

    assert value(3.0) == pytest.approx(value(1.0))
