#!/usr/bin/env bash
#
# Updates every Docker container running the cloudflare/cloudflared image.
#
#   sudo bin/update-cloudflared-containers.sh           update now
#   sudo bin/update-cloudflared-containers.sh install   install as a nightly
#                                                       root cron job and update now
#
# Per container: pull the image, and when it changed recreate the container
# with docker compose. If the tunnel does not reconnect, the previous image is
# put back and the container recreated again, so the device stays reachable.
# Containers started with plain 'docker run' are reported but not recreated
# (their original options are not known); containers pinned to a version tag
# or digest are left alone.

set -uo pipefail

SCRIPT_PATH="/usr/local/bin/update-cloudflared-containers"
LOG_FILE="/var/log/cloudflared-containers-update.log"
CRON_TIME="30 4 * * *"
WAIT_SECONDS=60
IMAGE_PATTERN='^(docker\.io/)?cloudflare/cloudflared(:[^@]+)?(@.+)?$'

log() {
    echo "$(date '+%F %T') $*"
}

compose() {
    if docker compose version > /dev/null 2>&1; then
        docker compose "$@"
    else
        docker-compose "$@"
    fi
}

# Recreate the compose service that owns the container
recreate() {
    local container="$1"
    local project workdir files service
    project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$container")
    workdir=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container")
    files=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$container")
    service=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$container")

    local args=(-p "$project" --project-directory "$workdir")
    local file
    IFS=',' read -ra config_files <<< "$files"
    for file in "${config_files[@]}"; do
        args+=(-f "$file")
    done

    compose "${args[@]}" up -d --force-recreate --no-deps "$service"
}

# Wait until the tunnel has reconnected. cloudflared logs "Registered tunnel
# connection" when it is up; without that line (e.g. a quieter log level) the
# container must at least keep running without restarts.
wait_for_tunnel() {
    local name="$1"
    local since="$2"
    local started i

    started=$(docker inspect -f '{{.State.StartedAt}}' "$name" 2>/dev/null) || return 1
    for ((i = 0; i < WAIT_SECONDS; i += 5)); do
        sleep 5
        if docker logs --since "$since" "$name" 2>&1 | grep -q "Registered tunnel connection"; then
            return 0
        fi
    done

    [ "$(docker inspect -f '{{.State.Running}} {{.State.Restarting}} {{.State.StartedAt}}' "$name" 2>/dev/null)" \
        == "true false $started" ]
}

update_containers() {
    local -A pulled=()
    local found=0 id name ref old_id new_id since

    while read -r id name ref; do
        [[ "$ref" =~ $IMAGE_PATTERN ]] || continue
        found=1

        if [[ "$ref" == *@* ]]; then
            log "$name: pinned to a digest ($ref), skipped"
            continue
        fi
        local tag="${ref##*cloudflared}"
        tag="${tag#:}"
        if [ -n "$tag" ] && [ "$tag" != "latest" ]; then
            log "$name: pinned to version '$tag', skipped (use :latest to update automatically)"
            continue
        fi

        if [ -z "${pulled[$ref]:-}" ]; then
            log "pulling $ref"
            if ! docker pull -q "$ref" > /dev/null; then
                log "$name: pulling $ref failed, skipped"
                continue
            fi
            pulled[$ref]=1
        fi

        old_id=$(docker inspect -f '{{.Image}}' "$id")
        new_id=$(docker image inspect -f '{{.Id}}' "$ref")
        if [ "$old_id" == "$new_id" ]; then
            log "$name: up to date"
            continue
        fi

        if [ -z "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id")" ]; then
            log "$name: new image available, but the container was not started with docker compose; recreate it manually"
            continue
        fi

        log "$name: new image, recreating"
        since=$(date +%s)
        if ! recreate "$id"; then
            log "$name: recreating failed, restoring previous image"
        elif wait_for_tunnel "$name" "$since"; then
            log "$name: updated, tunnel connected"
            docker image rm "$old_id" > /dev/null 2>&1 || true
            continue
        else
            log "$name: tunnel did not reconnect within ${WAIT_SECONDS}s, restoring previous image"
        fi

        # Roll back: point the tag at the old image again and recreate
        docker tag "$old_id" "$ref"
        id=$(docker ps -aq --filter "name=^${name}$" | head -n 1)
        if [ -n "$id" ] && recreate "$id"; then
            log "$name: previous image restored"
        else
            log "$name: ROLLBACK FAILED, check this container by hand"
        fi
    done < <(docker ps --format '{{.ID}} {{.Names}} {{.Image}}')

    if [ "$found" -eq 0 ]; then
        log "no running cloudflare/cloudflared containers found"
    fi
}

install_cron() {
    cp "$0" "$SCRIPT_PATH"
    chmod 755 "$SCRIPT_PATH"

    # Replace any existing entry
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" || true
     echo "$CRON_TIME $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -

    log "installed $SCRIPT_PATH, runs daily ($CRON_TIME), log: $LOG_FILE"
}

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo $0 ${1:-}"
    exit 1
fi
if ! command -v docker > /dev/null; then
    echo "docker not found"
    exit 1
fi

case "${1:-}" in
    "")
        update_containers
        ;;
    install)
        install_cron
        update_containers 2>&1 | tee -a "$LOG_FILE"
        ;;
    *)
        echo "Usage: sudo $0 [install]"
        exit 1
        ;;
esac
