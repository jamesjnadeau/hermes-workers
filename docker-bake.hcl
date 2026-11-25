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
