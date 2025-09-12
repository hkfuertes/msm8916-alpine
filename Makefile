builder: 
	docker build -t uz801-debian-alpine .
	docker run --rm -it --privileged -v ${PWD}:/builder -w /builder uz801-debian-alpine
