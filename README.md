# Shellcheck Action

## Usage

Add the following to your GIthub Actions workflows:

```yaml
steps:
  - uses: actions/checkout@master
  - name: ShellCheck Action
    uses: fearphage/shellcheck-action@0.0.4
    env:
      GITHUB_TOKEN: ${{secrets.GITHUB_TOKEN}}
```

## Acknowledgements:

* Shellcheck - https://github.com/koalaman/shellcheck
