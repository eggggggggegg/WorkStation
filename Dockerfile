FROM linuxmintd/mint22-amd64:latest

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/workstation \
    USER=workstation \
    DISPLAY=:99

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 sudo curl wget git ca-certificates python3 python3-pip python3-venv \
    firefox xterm dwm x11-xserver-utils x11-utils xdotool xauth xvfb \
    libgl1 libegl1 libgbm1 libdrm2 libva2 libva-drm2 libva-x11-2 \
    libx11-6 libxext6 libxfixes3 libxdamage1 \
    libxcomposite1 libxrandr2 libxi6 libxtst6 libxcb1 libpulse0 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash workstation \
    && usermod -aG sudo workstation \
    && echo "workstation ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/workstation \
    && chmod 0440 /etc/sudoers.d/workstation \
    && python3 -m venv /opt/selkies \
    && /opt/selkies/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/selkies/bin/pip install --no-cache-dir selkies==2.0.0 \
    && ln -sf /opt/selkies/bin/selkies /usr/local/bin/selkies \
    && ln -sf /opt/selkies/bin/selkies-session /usr/local/bin/selkies-session

COPY start-workstation.sh /usr/local/bin/start-workstation
RUN chmod +x /usr/local/bin/start-workstation

USER workstation
WORKDIR /home/workstation
EXPOSE 8080

CMD ["/usr/local/bin/start-workstation"]
