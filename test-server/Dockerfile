# Local stand-in for the app server: a bare Ubuntu 24.04 "VM" with systemd,
# SSH and Python only (what a fresh cloud VM ships with). Docker and the
# portal are installed later by Ansible, never by hand.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker

RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv openssh-server sudo python3 \
 && rm -rf /var/lib/apt/lists/*

# The image's default "ubuntu" user acts like the login user on a cloud VM
RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu

# Key-only SSH: password login is disabled
RUN printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' \
      > /etc/ssh/sshd_config.d/10-lab.conf

# Public key of the control node (public, so safe to bake in)
ARG SSH_PUBKEY
RUN test -n "$SSH_PUBKEY" \
 && install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.ssh \
 && echo "$SSH_PUBKEY" > /home/ubuntu/.ssh/authorized_keys \
 && chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys \
 && chmod 0600 /home/ubuntu/.ssh/authorized_keys

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
