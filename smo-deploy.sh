#!/bin/bash
	apt-get update
	apt-get install git -y
	git clone https://github.com/EdikGres/smo.git
	cd ./smo
	tar -xf dep.tar -C ~
	cd ~/dep/tools/k8s/bin/
	chmod 777 ./k8s-1node-cloud-init-k_1_15-h_2_17-d_cur.sh
	sed -i -e '/reboot/d' ./k8s-1node-cloud-init-k_1_15-h_2_17-d_cur.sh
	./k8s-1node-cloud-init-k_1_15-h_2_17-d_cur.sh

	docker pull myarmolovich/filebeat:5.5.0
	docker tag myarmolovich/filebeat:5.5.0 docker.elastic.co/beats/filebeat:5.5.0
	cd ~/dep/smo/bin
	chmod 777 ./install
	./install initlocalrepo
	cp -R /root/dep/smo/bin/smo-deploy/smo-oom/kubernetes/helm/plugins/ /root/.helm
	echo "Take coffee"
	./install
