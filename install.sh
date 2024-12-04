#!/bin/bash

# === Конфигурация ===
proxy=true
proxy_address="http://100.100.100.100:3128"
log_file="setup_docker_proxy.log"

# === Функции ===

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_file"
}

setup_apt_proxy() {
    log "Настраиваем прокси для APT..."
    sudo tee /etc/apt/apt.conf.d/95proxy > /dev/null <<EOF
Acquire::http::Proxy "$proxy_address";
Acquire::https::Proxy "$proxy_address";
EOF
    log "Прокси для APT настроен."
}

remove_apt_proxy() {
    log "Удаляем прокси для APT..."
    sudo rm -f /etc/apt/apt.conf.d/95proxy
    log "Прокси для APT удалён."
}

install_docker() {
    log "Устанавливаем Docker..."
    if [ "$proxy" = true ]; then
        log "Используем прокси для скачивания Docker GPG-ключа..."
        curl --proxy $proxy_address -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
    else
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
    fi

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    log "Добавляем репозиторий Docker..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log "Docker установлен."
}


install_docker_compose() {
    log "Устанавливаем последнюю версию Docker Compose..."
    if [ "$proxy" = true ]; then
        log "Используем прокси для скачивания Docker Compose..."
        curl --proxy $proxy_address -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    else
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    fi

    sudo chmod +x /usr/local/bin/docker-compose
    log "Docker Compose установлен."
}

setup_docker_proxy() {
    log "Настраиваем прокси для Docker..."
    sudo mkdir -p /etc/systemd/system/docker.service.d

    sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null <<EOF
[Service]
Environment="HTTP_PROXY=$proxy_address"
Environment="HTTPS_PROXY=$proxy_address"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart docker
    log "Прокси для Docker настроен."
}

remove_docker_proxy() {
    log "Удаляем настройки прокси для Docker..."
    sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    log "Прокси для Docker удалён."
}

setup_system_proxy() {
    log "Настраиваем системный прокси..."
    sudo tee /etc/environment > /dev/null <<EOF
HTTP_PROXY=$proxy_address
HTTPS_PROXY=$proxy_address
NO_PROXY=localhost,127.0.0.1
EOF
    source /etc/environment
    log "Системный прокси настроен."
}

remove_system_proxy() {
    log "Удаляем системный прокси..."
    sudo sed -i '/HTTP_PROXY/d' /etc/environment
    sudo sed -i '/HTTPS_PROXY/d' /etc/environment
    sudo sed -i '/NO_PROXY/d' /etc/environment
    source /etc/environment
    log "Системный прокси удалён."
}

check_docker() {
    log "Проверяем работу Docker..."
    sudo docker info | grep -i proxy || log "Прокси не настроен для Docker."
}

test_docker_pull() {
    log "Тестируем загрузку образа Docker..."
    sudo docker pull hello-world && log "Тестовая загрузка прошла успешно." || log "Не удалось загрузить образ hello-world."
}

# === Логика ===

start_time=$(date +%s)

log "Начало выполнения скрипта."

# Настройка прокси для APT и curl
if [ "$proxy" = true ]; then
    setup_apt_proxy
    setup_system_proxy
else
    remove_apt_proxy
    remove_system_proxy
fi

# Установка Docker и Docker Compose, если они не установлены
if ! command -v docker &> /dev/null; then
    install_docker
else
    log "Docker уже установлен."
fi

if ! command -v docker-compose &> /dev/null; then
    install_docker_compose
else
    log "Docker Compose уже установлен."
fi

# Настройка прокси для Docker
if [ "$proxy" = true ]; then
    setup_docker_proxy
else
    remove_docker_proxy
fi

# Проверка и тест
check_docker
test_docker_pull

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

log "Скрипт выполнен за $elapsed_time секунд."
log "Настройка завершена!"
