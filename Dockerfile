FROM linuxmintd/mint22-amd64:latest

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/workstation \
    USER=workstation

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 sudo curl wget git ca-certificates \
    firefox xterm x11vnc xvfb fluxbox \
    procps psmisc iproute2 net-tools \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash workstation \
    && usermod -aG sudo workstation \
    && echo "workstation ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/workstation \
    && chmod 0440 /etc/sudoers.d/workstation

COPY start-workstation.sh /usr/local/bin/start-workstation
RUN chmod +x /usr/local/bin/start-workstation

USER workstation
WORKDIR /home/workstation
EXPOSE 5900

CMD ["/usr/local/bin/start-workstation"]
