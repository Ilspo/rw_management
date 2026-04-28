#!/bin/bash
set -e

echo "=== Installing Vector ==="

# 1. Install Vector
curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash

# 2. Detect Vector path
VECTOR_BIN=$(which vector || true)

if [ -z "$VECTOR_BIN" ]; then
  echo "Vector not found in PATH, trying /root/.vector/bin/vector"
  VECTOR_BIN="/root/.vector/bin/vector"
fi

echo "Vector binary: $VECTOR_BIN"

# 3. Create directories
mkdir -p /root/.vector/data
mkdir -p /root/.vector/config

# 4. Write config
cat > /root/.vector/config/vector.yaml << 'EOF'
data_dir: "/root/.vector/data"

sources:
  system_logs:
    type: file
    include:
      - /var/log/syslog
      - /var/log/auth.log
      - /var/log/kern.log
      - /var/log/ufw.log

  remnanode_logs:
    type: file
    include:
      - /var/log/remnanode/access.log
      - /var/log/remnanode/error.log

  docker_logs:
    type: docker_logs

transforms:
  normalize:
    type: remap
    inputs:
      - system_logs
      - remnanode_logs
      - docker_logs
    source: |
      .host = get_hostname!()

      if exists(.file) {
        .source_type = "file"
      } else {
        .source_type = "docker"
      }

      if contains(string!(.file), "remnanode") {
        .service = "remnanode"
      } else {
        .service = "system"
      }

sinks:
  loki:
    type: loki
    inputs:
      - normalize
    endpoint: "http://78.109.17.154:3100"
    encoding:
      codec: json
    labels:
      job: "vector"
      host: "{{ host }}"
      service: "{{ service }}"
      source: "{{ source_type }}"
EOF

echo "Config written"

# 5. Create systemd service (if not exists)
cat > /etc/systemd/system/vector.service << EOF
[Unit]
Description=Vector Observability Data Pipeline
After=network.target

[Service]
ExecStart=$VECTOR_BIN --config /root/.vector/config/vector.yaml
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 6. Permissions
chmod +x $VECTOR_BIN

# 7. Enable + start
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vector
systemctl restart vector

# 8. Status
systemctl status vector --no-pager

echo "=== DONE ==="
