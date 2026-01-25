# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- YAML configuration file support (`diffdash.yml`) for shared team configuration
- New `--config` CLI flag to specify custom config file path
- Configurable file filtering: `ignore_paths`, `include_paths`, `excluded_suffixes`, `excluded_directories`
- Configuration file discovery (current dir, git root, explicit path)
- Example configuration file (`diffdash.example.yml`)
- Grafana v1 golden fixture contract test
- Adapter isolation spec
- Hard-fail on missing branch name

### Removed
- Deprecated Grafana renderer wrapper
- Deprecated CLI wrapper
