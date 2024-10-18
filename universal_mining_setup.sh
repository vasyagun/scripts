#!/bin/bash
source /etc/environment

# Параметры
GPU_WALLET="PLACEHOLDER_GPU_WALLET"
GPU_POOL="PLACEHOLDER_GPU_POOL"
WORKER="$(hostname)"
DIR="/root/hive/miners/custom/apoolminer_hiveos_autoupdate"
LOG_FILE="/var/log/miner/apoolminer_hiveos_autoupdate/apoolminer.log"
LOG_SCRIPT="/var/log/miner/apoolminer_hiveos_autoupdate/qubscript.log"
QUBIC_GPU_SCRIPT="$DIR/QUBICdualGPU.sh"

# Функция для логирования
log() {
    echo "$(date): $1" >> "$LOG_SCRIPT"
}

# Функция для мониторинга процесса miner
monitor_miner() {
    local miner_running=false
    local mining_state=""

    # Проверка наличия файла лога
    while [ ! -f "$LOG_FILE" ]; do
        log "Лог-файл не найден: $LOG_FILE. Ожидание появления файла..."
        sleep 10  # Ждем перед следующей проверкой
    done

    log "Лог-файл найден: $LOG_FILE. Начинаем мониторинг..."

    while true; do
        if pgrep -f "aleo_prover" > /dev/null; then
            if [ "$miner_running" = false ]; then
                log "Процесс aleo_prover запущен. Начинаем мониторинг лога..."
                miner_running=true
            fi

            sleep 30  # Ждем перед проверкой лога

            # Получаем последние 20 строк из лог-файла
            last_lines=$(tail -n 20 "$LOG_FILE")

            if echo "$last_lines" | grep -q "qubic mining idle now!"; then
                if [ "$mining_state" != "idle" ]; then
                    log "Qubic mining idle now! Перезапуск ALEO майнера."
                    # Перезапуск miner
                    screen -S miner -X stuff $'\003'
                    sleep 5
                    screen -dmS QUBICdualGPU bash "$QUBIC_GPU_SCRIPT"
                    mining_state="idle"
                fi
            elif echo "$last_lines" | grep -q "qubic mining work now!"; then
                if [ "$mining_state" != "work" ]; then
                    log "Qubic mining work now! Остановка ALEO майнера."
                    screen -S QUBICdualGPU -X stuff $'\003'
                    sleep 5
                    screen -S miner -X stuff $'\003'  # Перезапускаем miner после остановки процессов
                    mining_state="work"
                fi
            elif echo "$last_lines" | grep -q "out of memory"; then
                if [ "$mining_state" != "work" ]; then
                    log "Out of memory detected. Остановка ALEO майнера."
                    screen -S QUBICdualGPU -X stuff $'\003'
                    mining_state="work"
                fi
            fi

        else
            if [ "$miner_running" = true ]; then
                log "Процесс aleo_prover не запущен."
                miner_running=false
            fi
            # Останавливаем процессы QUBICdualGPU, если miner не запущен
            screen -S QUBICdualGPU -X stuff $'\003'
        fi

        sleep 10  # Проверяем каждые 10 секунд, запущен ли процесс miner
    done
}

# Запуск майнера и мониторинга
screen -dmS miner bash "$QUBIC_GPU_SCRIPT"
monitor_miner

