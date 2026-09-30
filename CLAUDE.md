# Overview

MapTiler SPECK is a software for producing technical documentation.
It is implemented as a Lua filter for Pandoc, with a small wrapper shell script, and a Lua binding to the Pikchr diagram drawing library.
The source code is in the `src/` directory.
This repository also defines a GitHub action in `action.yml`.

# Environment

You are inside a Docker container.
The `jail` file in this directory contains the script that started the container.
The Docker image has everything needed to work on the project.

You do not have the credentials necessary to access GitHub.
Do not even try, all development will be local only.

# Testing

The `doc/` directory contains an example of the kind of documents SPECK can handle.
The command below will execute SPECK and generate a `test_build/` output directory from the `doc/build.yaml` input.

```
src/speck doc/build.yaml test_build
```
