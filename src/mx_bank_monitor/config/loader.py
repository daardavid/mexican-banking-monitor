from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import BaseModel, ValidationError
from yaml.constructor import ConstructorError
from yaml.nodes import MappingNode

from mx_bank_monitor.config.models import (
    ConceptsDocument,
    ConfigBundle,
    DefinitionLifecycle,
    InstitutionsDocument,
    MappingsDocument,
    MetricsDocument,
    ReportingScopesDocument,
    SourcesDocument,
)


class ConfigValidationError(ValueError):
    """A deterministic, user-correctable editorial configuration failure."""


class UniqueKeySafeLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate mapping keys."""


def _construct_unique_mapping(
    loader: UniqueKeySafeLoader, node: MappingNode, deep: bool = False
) -> dict[object, object]:
    loader.flatten_mapping(node)
    mapping: dict[object, object] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            duplicate = key in mapping
        except TypeError as error:
            raise ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "found an unhashable mapping key",
                key_node.start_mark,
            ) from error
        if duplicate:
            raise ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeySafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)

DOCUMENTS: tuple[tuple[str, type[BaseModel]], ...] = (
    ("sources.yml", SourcesDocument),
    ("institutions.yml", InstitutionsDocument),
    ("reporting_scopes.yml", ReportingScopesDocument),
    ("concepts.yml", ConceptsDocument),
    ("mappings.yml", MappingsDocument),
    ("metrics.yml", MetricsDocument),
)


def _format_validation_error(path: Path, error: ValidationError) -> str:
    messages: list[str] = []
    for detail in error.errors(include_url=False, include_input=False):
        location = ".".join(str(part) for part in detail["loc"]) or "document"
        messages.append(f"{path}: {location}: {detail['msg']}")
    return "\n".join(messages)


def _format_yaml_error(path: Path, error: yaml.YAMLError) -> str:
    problem = getattr(error, "problem", None) or "invalid YAML syntax"
    mark = getattr(error, "problem_mark", None)
    location = ""
    if mark is not None:
        location = f" at line {mark.line + 1}, column {mark.column + 1}"
    return f"{path}: invalid YAML{location}: {problem}"


def _load_document[DocumentT: BaseModel](path: Path, model: type[DocumentT]) -> DocumentT:
    if not path.is_file():
        raise ConfigValidationError(f"missing required configuration file: {path}")
    try:
        raw = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeySafeLoader)
    except yaml.YAMLError as error:
        raise ConfigValidationError(_format_yaml_error(path, error)) from None
    except (OSError, UnicodeError) as error:
        raise ConfigValidationError(
            f"{path}: could not read configuration ({type(error).__name__})"
        ) from None
    try:
        return model.model_validate(raw)
    except ValidationError as error:
        raise ConfigValidationError(_format_validation_error(path, error)) from None


def load_config_bundle(
    config_dir: Path,
) -> ConfigBundle:
    """Load and cross-validate the complete version-controlled editorial bundle."""
    loaded: dict[str, BaseModel] = {}
    for filename, model in DOCUMENTS:
        loaded[filename.removesuffix(".yml")] = _load_document(config_dir / filename, model)

    try:
        bundle = ConfigBundle.model_validate(loaded)
    except ValidationError as error:
        raise ConfigValidationError(_format_validation_error(config_dir, error)) from None

    for metric in bundle.metrics.metrics:
        if metric.lifecycle == DefinitionLifecycle.ACTIVE:
            raise ConfigValidationError(
                f"{config_dir / 'metrics.yml'}: active metric {metric.code} cannot be validated "
                "before the executable metric registry exists"
            )
    for mapping in bundle.mappings.mappings:
        if (
            mapping.lifecycle == DefinitionLifecycle.ACTIVE
            and mapping.transformation_key is not None
        ):
            raise ConfigValidationError(
                f"{config_dir / 'mappings.yml'}: active mapping transformation "
                f"{mapping.transformation_key} cannot be validated before the executable "
                "transformation registry exists"
            )
    return bundle
