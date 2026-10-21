# ThoughtFarm work unit: OpenCode + the hospital client + tmux, polling the swarm board every 10 minutes.
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends tmux python3 curl ca-certificates util-linux procps bash \
    && rm -rf /var/lib/apt/lists/* \
    && (userdel -r ubuntu 2>/dev/null || true) && useradd -m -u 1000 -s /bin/bash agent \
    && mkdir -p /data /home/agent/.local/share/opencode /home/agent/projects && chown -R agent:agent /data /home/agent
USER agent
ENV HOME=/home/agent
RUN curl -fsSL https://opencode.ai/install | bash && $HOME/.opencode/bin/opencode upgrade --major
USER root
COPY build/staging/shared/usr/local/bin/sysmedic-hospital /usr/local/share/sysmedic-hospital-client.py
COPY tools/agentkit/ /opt/agentkit/
RUN printf '#!/bin/sh\nexec python3 /usr/local/share/sysmedic-hospital-client.py "$@"\n' > /usr/local/bin/sysmedic-hospital \
    && chmod +x /usr/local/bin/sysmedic-hospital /opt/agentkit/docker/entrypoint.sh
USER agent
WORKDIR /home/agent
ENV SYSMEDIC_HOSPITAL_DIR=/data/hospital
ENTRYPOINT ["/opt/agentkit/docker/entrypoint.sh"]
