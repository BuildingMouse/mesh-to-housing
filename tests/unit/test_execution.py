import multiprocessing

import pytest

from mesh_to_housing import Execution
from mesh_to_housing.execution import map_chunks, share, worker_count

pytestmark = pytest.mark.skipif("fork" not in multiprocessing.get_all_start_methods(), reason="workers need fork")


def _shifted(chunk, offset):
    return [value + offset.get() for value in chunk]


def test_workers_give_serial_results_in_order():
    with Execution(workers=2):
        assert map_chunks(_shifted, range(20), share(7)) == [value + 7 for value in range(20)]


def test_nested_scopes_restore_the_outer_workers():
    before = worker_count()
    with Execution(workers=2):
        assert worker_count() == 2
        with Execution(workers=1):
            assert worker_count() == 1
        assert worker_count() == 2
    assert worker_count() == before
