# dev:alpine — default:alpine + git set up to authenticate to GitHub through gh.
# No token is baked in. gh reads GITHUB_TOKEN / GH_TOKEN from the environment, which the
# Hermes profile forwards at runtime:
#   terminal:
#     docker_image: ghcr.io/jamesjnadeau/hermes-workers/dev:alpine
#     docker_forward_env: [GITHUB_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL]
FROM parent

USER root

RUN for host in https://github.com https://gist.github.com; do \
      git config --system "credential.$host.helper" '' ; \
      git config --system --add "credential.$host.helper" '!gh auth git-credential' ; \
    done
