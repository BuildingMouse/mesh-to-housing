"""Runs one fit and reports the time and memory peak of each part."""
import argparse
import resource
import time
from pathlib import Path

import numpy as np

from mesh_to_housing import Cuboid, FittingPipeline, FittingTask, MeshLoader, TransformConstraints, resize_mesh

from .profiler import FitProfiler

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pipeline", nargs="?", default=ROOT / "pipelines/staged_refine.yaml", type=Path)
    parser.add_argument("--mesh", default=ROOT / "mesh-assets/dinosaur.dae", type=Path)
    parser.add_argument("--size", default=10.0, type=float, help="the target's longest side")
    parser.add_argument("--items", default=100, type=int, help="the item budget")
    parser.add_argument("--kinds", default=6, type=int,
                        help="catalog size: a floor tile plus random cuboids, the same ones for every run")
    parser.add_argument("--scales", default=(0.2, 2.0), nargs=2, type=float)
    parser.add_argument("--resolution", type=int, help="use this resolution for every grid in the pipeline")
    parser.add_argument("--seed", default=42, type=int)
    parser.add_argument("--no-trace", action="store_true",
                        help="skip tracemalloc for faster, truer timings; only sampled RSS is reported")
    parser.add_argument("--all", action="store_true", help="list every part, however small")
    parser.add_argument("--json", type=Path, help="also save the parts as JSON here")
    args = parser.parse_args()

    pipeline = FittingPipeline.load(args.pipeline)
    if args.resolution:
        pipeline = with_resolution(pipeline, args.resolution)
    with FitProfiler(trace=not args.no_trace) as profiler:
        with profiler.part("load target"):
            mesh = MeshLoader.load(args.mesh)
            task = FittingTask(resize_mesh(mesh, args.size), catalog(args.kinds), args.items,
                               TransformConstraints(scale_bounds=tuple(args.scales)))
        began = time.perf_counter()
        construction = pipeline.fit(task, seed=args.seed)
        seconds = time.perf_counter() - began
        report = pipeline.evaluate(task, construction)

    print(f"{args.pipeline.name} on {args.mesh.name}: {len(construction)} of {args.items} items, {len(task.catalog)} "
          f"kinds, fit in {seconds:.1f} s, max RSS {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2 ** 20:.2f} GB")
    print("  " + ", ".join(f"{name} {value:.4f}" for name, value in report.metrics.items()))
    print()
    print(profiler.table(everything=args.all))
    print()
    print(profiler.heaviest())
    if args.json:
        profiler.save(args.json)


def catalog(kinds: int) -> tuple:
    rng = np.random.default_rng(0)
    items = [Cuboid("floor_tile", dimensions=(2.0, 2.0, 0.43322))]
    items += [Cuboid(f"item{number}", dimensions=tuple(np.round(rng.uniform(0.2, 2.0, 3), 3)))
              for number in range(1, kinds)]
    return tuple(items)


def with_resolution(pipeline: FittingPipeline, resolution: int) -> FittingPipeline:
    def change(value):
        if isinstance(value, dict):
            return {key: ({**item, "resolution": resolution} if key == "grid" and isinstance(item, dict)
                          else change(item)) for key, item in value.items()}
        if isinstance(value, list):
            return [change(item) for item in value]
        return value

    return FittingPipeline.from_data(change(pipeline.to_data(full=True)))


if __name__ == "__main__":
    main()
