#!/bin/bash
source /etc/environment

# Получение параметров из аргументов командной строки
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

# Проверка, что параметры были переданы
if [ -z "$GPU_WALLET" ] || [ -z "$GPU_POOL" ]; then
    echo "Необходимы параметры GPU_WALLET и GPU_POOL."
    exit 1
fi

# Параметры
LOG_FILE="/var/log/miner/apoolminer_hiveos_autoupdate/apoolminer.log"
WORKER="$(hostname)"
DIR="/root/hive/miners/custom/scripts"
QUBIC_GPU_SCRIPT="$DIR/QUBICdualGPU.sh"
PID_FILE="/tmp/monitor_miner.pid"

# Проверка наличия директории и создание, если отсутствует
if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
    echo "Создана папка: $DIR"
fi

# Создание скрипта для майнера ALEO
if [ ! -f "$QUBIC_GPU_SCRIPT" ]; then
    echo -e "#!/bin/bash\n/root/hive/miners/custom/aleo_prover/aleo_prover --pool $GPU_POOL --address $GPU_WALLET --custom_name $WORKER" > "$QUBIC_GPU_SCRIPT"
    chmod +x "$QUBIC_GPU_SCRIPT"
    echo "Создан файл: $QUBIC_GPU_SCRIPT"
fi

# Проверка, запущен ли уже мониторинг
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if [ -n "$PID" ] && kill -0 "$PID" > /dev/null 2>&1; then
        echo "Мониторинг уже запущен с PID: $PID"
        exit 0
    else
        echo "PID-файл найден, но процесс не работает. Перезапуск..."
        rm -f "$PID_FILE"
    fi
fi

# Запуск мониторинга в фоновом режиме
monitor_miner() {
    echo $$ > "$PID_FILE"  # Сохраняем PID текущего процесса

    local miner_running=false
    local mining_state=""

    # Ожидание появления лог-файла майнера QUBIC
    while [ ! -f "$LOG_FILE" ]; do
        echo "Лог-файл не найден: $LOG_FILE. Ожидание..."
        sleep 30
    done

    echo "Лог-файл найден: $LOG_FILE. Начинаем мониторинг..."

    while true; do
        # Проверяем, запущен ли процесс майнера QUBIC
        if pgrep -f "miner" > /dev/null; then
            if [ "$miner_running" = false ]; then
                echo "Процесс miner запущен. Начинаем мониторинг лога..."
                miner_running=true
            fi

            sleep 5  # Ждем перед проверкой лога

            # Читаем последние 20 строк из лог-файла
            last_lines=$(tail -n 20 "$LOG_FILE")

            if echo "$last_lines" | grep -q "qubic mining idle now!"; then
                if [ "$mining_state" != "idle" ]; then
                    echo "$(date): Начинается майнинг Aleo"
                    screen -dmS QUBICdualGPU bash "$QUBIC_GPU_SCRIPT"
                    mining_state="idle"
                fi
            elif echo "$last_lines" | grep -q "qubic mining work now!"; then
                if [ "$mining_state" != "work" ]; then
                    echo "$(date): Майнинг Qubic снова активен"
                    screen -S QUBICdualGPU -X stuff $'\003'
                    mining_state="work"
                fi
            elif echo "$last_lines" | grep -q "out of memory"; then
                if [ "$mining_state" != "work" ]; then
                    echo "$(date): Недостаточно памяти"
                    screen -S QUBICdualGPU -X stuff $'\003'
                    mining_state="work"
                fi
            fi

        else
            if [ "$miner_running" = true ]; then
                echo "Процесс miner не запущен."
                miner_running=false
            fi

            # Останавливаем процессы QUBICdualGPU, если miner не запущен
            screen -S QUBICdualGPU -X stuff $'\003'
        fi

        sleep 10  # Проверяем состояние каждые 10 секунд
    done
}

# Запуск мониторинга
monitor_miner &  # Запуск в фоновом режиме
