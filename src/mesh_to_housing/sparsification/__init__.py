from .farthest import farthest_point
from .normal_variation import normal_weighted
from .random import random_subset

METHODS = {
    "random": random_subset,
    "normal_variation": normal_weighted,
    "farthest": farthest_point,
}
