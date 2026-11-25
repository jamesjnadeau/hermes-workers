# Build everything:   docker buildx bake --load publish
# Build one image:    docker buildx bake --load dev-alpine
# Child images say `FROM parent`; `contexts` below decides what `parent` is.

variable "REGISTRY" { default = "ghcr.io/jamesjnadeau/hermes-workers" }
variable "DATE"     { default = "" }   # CI sets YYYYMMDD
variable "SHA"      { default = "" }   # CI sets the short commit sha

# <registry>/<image>:<distro>, plus :<distro>-<date> and :<distro>-<sha> when set.
function "tags" {
  params = [image, distro]
  result = concat(
    ["${REGISTRY}/${image}:${distro}"],
    DATE != "" ? ["${REGISTRY}/${image}:${distro}-${DATE}"] : [],
    SHA  != "" ? ["${REGISTRY}/${image}:${distro}-${SHA}"]  : [],
  )
}

target "_common" {
  platforms = ["linux/amd64"]
}

target "default-debian" {
  inherits = ["_common"]
  context  = "images/default/debian"
  tags     = tags("default", "debian")
}

target "default-alpine" {
  inherits = ["_common"]
  context  = "images/default/alpine"
  tags     = tags("default", "alpine")
}

target "dev-debian" {
  inherits = ["_common"]
  context  = "images/dev/debian"
  contexts = { parent = "target:default-debian" }
  tags     = tags("dev", "debian")
}

target "dev-alpine" {
  inherits = ["_common"]
  context  = "images/dev/alpine"
  contexts = { parent = "target:default-alpine" }
  tags     = tags("dev", "alpine")
}

# Everything CI pushes to the registry.
group "publish" {
  targets = ["default-debian", "default-alpine", "dev-debian", "dev-alpine"]
}

# Playdate: built locally only, never pushed (Panic's SDK license forbids redistribution).
# Locally its parent is the published dev:debian; CI overrides PLAYDATE_PARENT=target:dev-debian
# and INSTALL_SDK=0. The tag has no registry so it can't be pushed to GHCR by accident.
variable "PLAYDATE_PARENT" { default = "docker-image://ghcr.io/jamesjnadeau/hermes-workers/dev:debian" }
variable "INSTALL_SDK"     { default = "1" }

target "playdate-debian" {
  inherits = ["_common"]
  context  = "images/playdate/debian"
  contexts = { parent = PLAYDATE_PARENT }
  args     = { INSTALL_SDK = INSTALL_SDK }
  tags     = ["hermes-workers/playdate:debian"]
}

# What CI builds and tests (publish + playdate without the SDK).
group "ci" {
  targets = ["default-debian", "default-alpine", "dev-debian", "dev-alpine", "playdate-debian"]
}
