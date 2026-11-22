def pytest_addoption(parser):
    parser.addoption("--update-snapshots", action="store_true",
                     help="Save the current fit results as the new snapshots instead of comparing with them.")
