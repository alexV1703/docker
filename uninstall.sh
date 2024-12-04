#!/bin/bash

# === Конфигурация ===
proxy=true
proxy_address="http://100.100.100.100:3128"
log_file="uninstall_docker_proxy.log"

# === Функции ===

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_file"
}

confirm_removal() {
    echo "ВНИМАНИЕ: Всё, что связано с Docker, будет удалено, включая все версии, данные и настройки."
    read -p "Введите 'да' или 'yes', чтобы подтвердить удаление: " confirmation

    if [[ "$confirmation" != "да" && "$confirmation" != "yes" ]]; then
        log "Удаление отменено пользователем."
        exit 1
    fi
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
    if [ -f /etc/apt/apt.conf.d/95proxy ]; then
        log "Удаляем прокси для APT..."
        sudo rm -f /etc/apt/apt.conf.d/95proxy
        log "Прокси для APT удалён."
    else
        log "Прокси для APT уже отсутствует."
    fi
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
    if grep -q "HTTP_PROXY" /etc/environment; then
        log "Удаляем системный прокси..."
        sudo sed -i '/HTTP_PROXY/d' /etc/environment
        sudo sed -i '/HTTPS_PROXY/d' /etc/environment
        sudo sed -i '/NO_PROXY/d' /etc/environment
        source /etc/environment
        log "Системный прокси удалён."
    else
        log "Системный прокси уже отсутствует."
    fi
}

remove_docker_proxy() {
    if [ -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then
        log "Удаляем настройки прокси для Docker..."
        sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf
        sudo systemctl daemon-reload
        if systemctl is-active --quiet docker; then
            sudo systemctl restart docker
            log "Прокси для Docker удалён."
        else
            log "Docker не запущен, но настройки прокси удалены."
        fi
    else
        log "Настройки прокси для Docker уже отсутствуют."
    fi
}

stop_and_remove_docker() {
    log "Останавливаем Docker..."
    sudo systemctl stop docker 2>/dev/null || log "Docker уже остановлен или не установлен."

    log "Удаляем Docker и связанные пакеты..."
    sudo apt update
    sudo apt purge -y docker* containerd* runc* docker-ce* docker-ce-cli* docker-compose* docker-buildx-plugin*
    sudo apt autoremove -y
    log "Все версии Docker и связанные пакеты удалены."
}

clean_docker_data() {
    if [ -d /var/lib/docker ] || [ -d /var/lib/containerd ]; then
        log "Очищаем данные Docker..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
        log "Данные Docker полностью удалены."
    else
        log "Данные Docker уже отсутствуют."
    fi
}

clean_remaining_files() {
    if [ -d /etc/docker ] || [ -e /var/run/docker.sock ]; then
        log "Удаляем оставшиеся файлы Docker..."
        sudo rm -rf /etc/docker
        sudo rm -rf /var/run/docker.sock
        log "Оставшиеся файлы Docker удалены."
    else
        log "Оставшиеся файлы Docker уже отсутствуют."
    fi
}

# === Логика ===

start_time=$(date +%s)

log "Начало удаления Docker и связанных компонентов."

# Подтверждение удаления
confirm_removal

# Настройка прокси для APT и системы
if [ "$proxy" = true ]; then
    setup_apt_proxy
    setup_system_proxy
fi

# Удаление Docker и Docker Compose
stop_and_remove_docker

# Очистка данных и оставшихся файлов
clean_docker_data
clean_remaining_files

# Удаление настроек прокси
remove_apt_proxy
remove_system_proxy
remove_docker_proxy

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

log "Скрипт выполнен за $elapsed_time секунд."
log "Удаление завершено!"
