#!/bin/bash
apt update -y && apt install -y screen git curl cron nano mc htop iputils-ping
cd /root/
mkdir qub
cd qub
wget https://github.com/apool-io/apoolminer/releases/download/v2.6.2/apoolminer_linux_autoupdate_v2.6.2.tar.gz
wget https://github.com/6block/zkwork_aleo_gpu_worker/releases/download/cuda-v0.2.4/aleo_prover-v0.2.4_cuda_full.tar.gz
mkdir ap
rm ./ap/*
tar -xf apoolminer_linux_autoupdate_v2.6.2.tar.gz
tar -xf aleo_prover-v0.2.4_cuda_full.tar.gz aleo_prover/aleo_prover
cp ./aleo_prover/aleo_prover ./ap/aleo_prover
cp ./apoolminer_linux_autoupdate_v2.6.2/* ./ap/
rm -R apoolminer_linux_autoupdate_v2.6.2
rm -R aleo_prover
cd ap
rm miner.conf
rm run.sh
cd ..
cd ap
curl -OL https://raw.githubusercontent.com/rakot7/rentalscripts/main/run.sh
cat <<EOF > miner.conf
algo=qubic
account=CP_3kv3xuwg6d
pool=qubic1.hk.apool.io:3334

worker = $1
cpu-off = true
#thread = 12
#gpu-off = false
#gpu = 0,1,2
mode = 1

third_miner = "aleo_prover"
third_cmd = "./aleo_prover --pool aleo.asia1.zk.work:10003 --pool aleo.hk.zk.work:10003 --pool aleo.jp.zk.work:10003 --address aleo1t5xv3n9z0aphypcsyk5mjevtqacxvnsytkpp5dzfqhulv0glnc8smx25fm --custom_name $1"
EOF
chmod +x ./run.sh
screen -dmS qub ./run.sh
echo "" >> /etc/supervisor/conf.d/supervisord.conf
echo "" >> /etc/supervisor/conf.d/supervisord.conf
echo "[program:qub]" >> /etc/supervisor/conf.d/supervisord.conf
echo "command=/bin/bash -c 'cd /root/qub/ap/ && screen -dmS qub ./run.sh && sleep infinity'" >> /etc/supervisor/conf.d/supervisord.conf
