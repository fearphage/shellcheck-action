FROM koalaman/shellcheck-alpine

LABEL com.github.actions.name="Shellcheck Action"
LABEL com.github.actions.description="Wraps the shellcheck CLI"
LABEL com.github.actions.icon="code"
LABEL com.github.actions.color="red"

LABEL maintainer="Phred <fearphage+ghaction@gmail.com>"
LABEL repository="https://github.com/fearphage/shellcheck-action"

RUN apk add --no-cache \
  bash \
  ca-certificates \
  curl \
  grep \
  jq

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
