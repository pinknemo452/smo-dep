#!/bin/bash
if [ "$1" == "install" ]
	then
	apt-get upadate
	apt-get install git -y
	git clone https://github.com/EdikGres/smo.git
	cd ./smo
	tar -xf dep.tar -C ~
	cd ~/dep/tools/k8s/bin/
	chmod 777 ./k8s-1node-cloud-init-k_1_15-h_2_17-d_cur.sh
	./k8s-1node-cloud-init-k_1_15-h_2_17-d_cur.sh
fi

if [ "$1" == "check" ]
	then
	kubectl get pods --all-namespaces
	echo "There should be 9 pods running in kube-system namespace."
fi

if [ "$1" == "deploy" ]
	then
	cd ~/dep/smo/bin
	chmod 777 ./install
	./install initlocalrepo
	cp -R /root/dep/smo/bin/smo-deploy/smo-oom/kubernetes/helm/plugins/ /root/.helm
	echo "Take coffee"
	./install
fi
