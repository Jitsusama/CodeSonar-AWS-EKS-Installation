# CodeSonar Image Base

CodeSonar is a static code analysis tool that helps developers identify and fix security
vulnerabilities and quality issues in their code. This repository provides a Dockerfile to create a
CodeSonar OCI (Open Container Initiative) base image layer. This composable layer is designed to be
used as a building block for creating custom SAST analysis images, but cannot be used directly. By
using this image as a base or intermediate stage for your own custom image, you can integrate SAST
analysis into your own build tooling images.

## Usage

To create a custom Dockerfile that uses the CodeSonar OCI base image layer, you will want to either
use an image published to this repository as a base (FROM) layer, or, bring in an image published to
this repository as a separate stage.

Take a look at the example [from-stage.Dockerfile][1] for how you can use this image as part of a
stage in a custom Linux (w/GCC) based Dockerfile, or look at the example [from-base.Dockerfile][2]
for an example of how to use this as a base for your own custom Linux based Dockerfile.

[1]: <./example/from-stage.Dockerfile>

[2]: <./example/from-base.Dockerfile>

## Building

To build this image, you can utilize standard OCI image generation tooling that supports the
Dockerfile syntax such as BuildKit, Docker Desktop or Kaniko. When building, you will need to pass
the following build arguments:

| Name            | Description                                                    | Example                                              |
|:----------------|:---------------------------------------------------------------|:-----------------------------------------------------|
| PACKAGE_BASEURI | Base-URI to this repository's GitLab generic package registry. | https://gitlab/api/v4/projects/1234/packages/generic |
| PACKAGE_TOKEN   | GitLab token with generic package read access.                 | super-secret                                         |
