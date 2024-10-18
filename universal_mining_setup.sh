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
DIR="/root/hive/miners/custom/apoolminer_hiveos_autoupdate"
LOG_FILE="/var/log/miner/apoolminer_hiveos_autoupdate/apoolminer.log"

# Создание директории, если отсутствует
mkdir -p "$DIR"

# Загрузка и распаковка майнера ALEO
echo "Скачивание и распаковка майнера ALEO..."
wget -O /tmp/aleo_prover.tar.gz https://github.com/6block/zkwork_aleo_gpu_worker/releases/download/v0.2.3-fix/aleo_prover-v0.2.3_full_fix.tar.gz
tar -xzf /tmp/aleo_prover.tar.gz -C "$DIR"
chmod +x "$DIR/aleo_prover/aleo_prover"

# Создание скрипта QUBICdualGPU.sh
QUBIC_GPU_SCRIPT="$DIR/QUBICdualGPU.sh"
echo "Создание скрипта QUBICdualGPU.sh..."
cat <<EOF > "$QUBIC_GPU_SCRIPT"
#!/bin/bash
/root/hive/miners/custom/apoolminer_hiveos_autoupdate/aleo_prover/aleo_prover --pool $GPU_POOL --address $GPU_WALLET --custom_name $WORKER
EOF
chmod +x "$QUBIC_GPU_SCRIPT"

# Создание основного скрипта мониторинга
MAIN_SCRIPT="$DIR/qubscript.sh"
echo "Создание основного скрипта мониторинга qubscript.sh..."
cat <<'EOF' > "$MAIN_SCRIPT"
#!/bin/bash
source /etc/environment

# Параметры
GPU_WALLET="PLACEHOLDER_GPU_WALLET"
GPU_POOL="PLACEHOLDER_GPU_POOL"
WORKER="$(hostname)"
DIR="/root/hive/miners/custom/apoolminer_hiveos_autoupdate"
LOG_FILE="/var/log/miner/apoolminer_hiveos_autoupdate/apoolminer.log"
QUBIC_GPU_SCRIPT="$DIR/QUBICdualGPU.sh"

# Функция для мониторинга процесса miner
monitor_miner() {
    local miner_running=false
    local mining_state=""

    # Проверка наличия файла лога
    while [ ! -f "$LOG_FILE" ]; do
        echo "Лог-файл не найден: $LOG_FILE. Ожидание появления файла..."
        sleep 10  # Ждем перед следующей проверкой
    done

    echo "Лог-файл найден: $LOG_FILE. Начинаем мониторинг..."

    while true; do
        if pgrep -f "aleo_prover" > /dev/null; then
            if [ "$miner_running" = false ]; then
                echo "Процесс aleo_prover запущен. Начинаем мониторинг лога..."
                miner_running=true
            fi

            sleep 30  # Ждем перед проверкой лога

            # Получаем последние 20 строк из лог-файла
            last_lines=$(tail -n 20 "$LOG_FILE")

            if echo "$last_lines" | grep -q "qubic mining idle now!"; then
                if [ "$mining_state" != "idle" ]; then
                    echo "$(date): Qubic mining idle now!"
                    # Перезапуск miner
                    screen -S miner -X stuff $'\003'
                    sleep 5
                    screen -dmS QUBICdualGPU bash "$QUBIC_GPU_SCRIPT"
                    mining_state="idle"                    
                fi
            elif echo "$last_lines" | grep -q "qubic mining work now!"; then
                if [ "$mining_state" != "work" ]; then
                    echo "$(date): Qubic mining work now!"
                    screen -S QUBICdualGPU -X stuff $'\003'
                    sleep 5
                    screen -S miner -X stuff $'\003'  # Перезапускаем miner после остановки процессов
                    mining_state="work"                 
                fi
            elif echo "$last_lines" | grep -q "out of memory"; then
                if [ "$mining_state" != "work" ]; then
                    echo "$(date): Out of memory detected"
                    screen -S QUBICdualGPU -X stuff $'\003'
                    mining_state="work"
                fi
            fi

        else
            if [ "$miner_running" = true ]; then
                echo "Процесс aleo_prover не запущен."
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
EOF

# Вставка реальных параметров в qubscript.sh
sed -i "s/PLACEHOLDER_GPU_WALLET/$GPU_WALLET/" "$MAIN_SCRIPT"
sed -i "s/PLACEHOLDER_GPU_POOL/$GPU_POOL/" "$MAIN_SCRIPT"
chmod +x "$MAIN_SCRIPT"

# Запуск основного скрипта в screen
echo "Запуск основного скрипта мониторинга в screen..."
screen -dmS qubscript bash "$MAIN_SCRIPT"

echo "Установка и настройка майнинга завершены."
