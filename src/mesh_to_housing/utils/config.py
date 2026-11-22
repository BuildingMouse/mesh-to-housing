from typing import Any

from pydantic import BaseModel, ConfigDict, ValidationError, model_serializer


class ConfigError(ValueError):
    """Raised for config data that can't be read. The message says where each problem is."""

    @classmethod
    def from_validation(cls, error: ValidationError, data: Any) -> "ConfigError":
        return cls("\n".join(f"{_location(detail['loc'], data)}: {_message(detail)}" for detail in error.errors()))


class Config(BaseModel):
    """Settings as plain, immutable values, checked when the config is made. Settings may also be given in
    order, as with a dataclass.

    The type field is always written first, because reading the config back needs it.
    """

    model_config = ConfigDict(frozen=True, extra="forbid")

    def __init__(self, *args: Any, **kwargs: Any):
        if args:
            names = [name for name in type(self).model_fields if name != "type"]
            if len(args) > len(names):
                raise TypeError(f"{type(self).__name__} takes at most {len(names)} settings in order")
            for name, value in zip(names, args):
                if name in kwargs:
                    raise TypeError(f"{type(self).__name__} got {name!r} twice")
                kwargs[name] = value
        super().__init__(**kwargs)

    @model_serializer(mode="wrap")
    def _serialize(self, handler):
        return _type_first(self, handler(self))

    def to_data(self, *, full: bool = False) -> dict:
        """The config as plain data for YAML. Defaults are left out unless full is set. Use full for saved
        results and cache keys, so their meaning doesn't change when a default does.
        """
        return _plain(self.model_dump(exclude_defaults=not full))

    @classmethod
    def from_data(cls, data: Any) -> "Config":
        """Read a config from plain data, raising ConfigError if the data doesn't fit."""
        try:
            return cls.model_validate(data)
        except ValidationError as error:
            raise ConfigError.from_validation(error, data) from None

    def to_yaml(self, *, full: bool = False) -> str:
        import yaml

        return yaml.safe_dump(self.to_data(full=full), sort_keys=False, default_flow_style=None, width=110)

    @classmethod
    def from_yaml(cls, text: str) -> "Config":
        import yaml

        return cls.from_data(yaml.safe_load(text))


def _type_first(config: BaseModel, data: Any) -> Any:
    kind = getattr(config, "type", None)
    if isinstance(kind, str) and isinstance(data, dict):
        return {"type": kind, **{name: value for name, value in data.items() if name != "type"}}
    return data


def _plain(value: Any) -> Any:
    if isinstance(value, (tuple, list)):
        return [_plain(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _plain(item) for key, item in value.items()}
    return value


def _location(location: tuple, data: Any) -> str:
    """The path to an error in the data, without the type tags that pydantic puts in paths through unions."""
    text = "config"
    for index, part in enumerate(location):
        has_more = index + 1 < len(location)
        if isinstance(data, list) and isinstance(part, int) and part < len(data):
            text, data = text + f"[{part}]", data[part]
        elif isinstance(data, dict) and part in data and not (has_more and isinstance(data[part], str)):
            text, data = text + f".{part}", data[part]
        elif not (isinstance(data, dict) and has_more):
            text, data = text + f".{part}", None
    return text


def _message(detail: dict) -> str:
    message = detail["msg"]
    return message[len("Value error, "):] if message.startswith("Value error, ") else message
