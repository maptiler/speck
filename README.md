# SPECK

Technical documentation tool.

## GitHub action

Inputs:

- `config`
- `target`
- `version`

Example:

```yaml
uses: maptiler/speck@v1
with:
  config: build.yaml
  target: build
  version: ${{ github.ref_name }}
```
