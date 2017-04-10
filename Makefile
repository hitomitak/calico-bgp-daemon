CALICO_BUILD?=hitomitak/go-build-ppc64le
SRC_FILES=$(shell find . -type f -name '*.go')
GOBGPD_VERSION?=$(shell git describe --tags --dirty)
PACKAGE_NAME?=github.com/projectcalico/calico-bgp-daemon
LOCAL_USER_ID?=$(shell id -u $$USER)
#CONTAINER_NAME?=calico/gobgpd
#

build-containerized: clean vendor dist/gobgp
	mkdir -p dist
	docker run --rm \
	-v $(CURDIR):/go/src/$(PACKAGE_NAME) \
	-v $(CURDIR)/dist:/go/src/$(PACKAGE_NAME)/dist \
	-e LOCAL_USER_ID=$(LOCAL_USER_ID) \
		$(CALICO_BUILD) sh -c '\
			cd /go/src/$(PACKAGE_NAME) && \
			make binary'
vendor: glide.yaml
	mkdir -p $(HOME)/.glide
	docker run --rm \
    -v $(CURDIR):/go/src/$(PACKAGE_NAME):rw \
    -v $(HOME)/.glide:/home/user/.glide:rw --entrypoint=sh \
    glide-ppc64le -c ' \
		  cd /go/src/$(PACKAGE_NAME) && \
      glide install -strip-vendor'


glide.yaml:
	docker build -t glide-ppc64le - < Dockerfile.glide

binary: dist/gobgpd

dist/gobgp:
	mkdir -p $(@D)
	docker run --rm -v $(CURDIR)/dist:/go/bin \
	-e LOCAL_USER_ID=$(LOCAL_USER_ID) \
	$(CALICO_BUILD) go get -v github.com/osrg/gobgp/gobgp

dist/gobgpd: $(SRC_FILES) 
	mkdir -p $(@D)
	go build -v -o dist/calico-bgp-daemon \
	-ldflags "-X main.VERSION=$(GOBGPD_VERSION) -s -w" main.go ipam.go

release: clean
ifndef VERSION
	$(error VERSION is undefined - run using make release VERSION=vX.Y.Z)
endif
	git tag $(VERSION)
	$(MAKE) $(CONTAINER_NAME) 
	# Check that the version output appears on a line of its own (the -x option to grep).
	# Tests that the "git tag" makes it into the binary. Main point is to catch "-dirty" builds
	@echo "Checking if the tag made it into the binary"
	docker run --rm calico/gobgpd -v | grep -x $(VERSION) || (echo "Reported version:" `docker run --rm calico/gobgpd -v` "\nExpected version: $(VERSION)" && exit 1)
	docker tag calico/gobgpd calico/gobgpd:$(VERSION)
	docker tag calico/gobgpd quay.io/calico/gobgpd:$(VERSION)
	docker tag calico/gobgpd quay.io/calico/gobgpd:latest

	@echo "Now push the tag and images. Then create a release on Github and attach the dist/gobgpd and dist/gobgp binaries"
	@echo "git push origin $(VERSION)"
	@echo "docker push calico/gobgpd:$(VERSION)"
	@echo "docker push quay.io/calico/gobgpd:$(VERSION)"
	@echo "docker push calico/gobgpd:latest"
	@echo "docker push quay.io/calico/gobgpd:latest"

clean:
	rm -rf vendor
	rm -rf dist
