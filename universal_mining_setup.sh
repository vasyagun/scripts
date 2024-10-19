#!/bin/bash

# Проверка, что скрипт выполняется от root
if [ "$(id -u)" -ne 0 ]; then
    echo "Скрипт должен быть запущен от root."
    exit 1
fi

# Загрузка параметров из аргументов
# Ожидаем, что параметры будут переданы в формате:
# ./universal_mining_setup.sh GPU_WALLET=<ваш_кошелек_GPU> GPU_POOL=<ваш_пул_GPU>

for ARG in "$@"
do
    case $ARG in
        GPU_WALLET=*)
            GPU_WALLET="${ARG#*=}"
            shift
            ;;
        GPU_POOL=*)
            GPU_POOL="${ARG#*=}"
            shift
            ;;
        *)
            ;;
    esac
done

# Проверка наличия необходимых параметров
if [ -z "$GPU_WALLET" ] || [ -z "$GPU_POOL" ]; then
    echo "Необходимы параметры GPU_WALLET и GPU_POOL."
    exit 1
fi

# Параметры
WORKER="$(hostname)"
DIR="/root/hive/miners/custom/aleo_miner"
LOG_DIR="/var/log/miner"  # Стандартная директория логов майнеров в Hive OS
QUBIC_LOG_FILE="$LOG_DIR/miner.log"  # Лог-файл майнера QUBIC
ALEO_LOG_FILE="$DIR/aleo_prover.log"

# Создание директории для майнера ALEO, если отсутствует
mkdir -p "$DIR"

# Загрузка и распаковка майнера ALEO
echo "Скачивание и распаковка майнера ALEO..."
wget -O /tmp/aleo_prover.tar.gz https://github.com/6block/zkwork_aleo_gpu_worker/releases/download/v0.2.3-fix/aleo_prover-v0.2.3_full_fix.tar.gz
tar -xzf /tmp/aleo_prover.tar.gz -C "$DIR"
chmod +x "$DIR/aleo_prover/aleo_prover"

# Создание скрипта запуска майнера ALEO
ALEO_MINER_SCRIPT="$DIR/aleo_miner.sh"
echo "Создание скрипта aleo_miner.sh..."
cat <<EOF > "$ALEO_MINER_SCRIPT"
#!/bin/bash
cd "$DIR/aleo_prover"
/root/hive/miners/custom/aleo_miner/aleo_prover/aleo_prover --pool $GPU_POOL --address $GPU_WALLET --custom_name $WORKER >> "$ALEO_LOG_FILE" 2>&1
EOF
chmod +x "$ALEO_MINER_SCRIPT"

# Создание скрипта мониторинга
MONITOR_SCRIPT="$DIR/monitor.sh"
echo "Создание скрипта мониторинга monitor.sh..."
cat <<'EOF' > "$MONITOR_SCRIPT"
#!/bin/bash

# Параметры
QUBIC_LOG_FILE="PLACEHOLDER_QUBIC_LOG_FILE"
ALEO_MINER_SCRIPT="PLACEHOLDER_ALEO_MINER_SCRIPT"

# Функция для мониторинга логов майнера QUBIC
monitor_qubic() {
    tail -n0 -F "$QUBIC_LOG_FILE" | while read LINE; do
        if echo "$LINE" | grep -q "qubic mining idle now!"; then
            echo "$(date): Detected idle state in QUBIC miner. Starting ALEO miner..."
            screen -dmS aleo_miner bash "$ALEO_MINER_SCRIPT"
        elif echo "$LINE" | grep -q "qubic mining work now!"; then
            echo "$(date): Detected work state in QUBIC miner. Stopping ALEO miner..."
            screen -S aleo_miner -X quit
        fi
    done
}

# Запуск мониторинга
monitor_qubic
EOF

# Вставка реальных путей в скрипт мониторинга
sed -i "s|PLACEHOLDER_QUBIC_LOG_FILE|$QUBIC_LOG_FILE|" "$MONITOR_SCRIPT"
sed -i "s|PLACEHOLDER_ALEO_MINER_SCRIPT|$ALEO_MINER_SCRIPT|" "$MONITOR_SCRIPT"
chmod +x "$MONITOR_SCRIPT"

# Запуск скрипта мониторинга в screen
echo "Запуск скрипта мониторинга в screen..."
screen -dmS monitor bash "$MONITOR_SCRIPT"

echo "Установка и настройка майнинга завершены."
