#!/bin/sh
set -e
set -o pipefail

WORKING_DIRECTORY="$PWD"

[ -z "$GITHUB_PAGES_BRANCH" ] && GITHUB_PAGES_BRANCH=gh-pages
[ -z "$HELM_CHARTS_SOURCE" ] && HELM_CHARTS_SOURCE="$WORKING_DIRECTORY/charts"
[ -d "$HELM_CHARTS_SOURCE" ] || {
  echo "ERROR: Could not find Helm chart in $HELM_CHARTS_SOURCE"
  exit 1
}
[ -z "$HELM_VERSION" ] && HELM_VERSION=2.13.1
[ -z "$KUBEVAL_VERSION" ] && KUBEVAL_VERSION=0.7.3
[ -z "$KUBERNETES_VERSION" ] && KUBERNETES_VERSION=1.14.0
[ "$CIRCLE_BRANCH" ] || {
  echo "ERROR: Environment variable CIRCLE_BRANCH is required"
  exit 1
}

echo "HELM_CHARTS_SOURCE=$HELM_CHARTS_SOURCE"
echo "HELM_VERSION=$HELM_VERSION"
echo "KUBERNETES_VERSION=$KUBERNETES_VERSION"
echo "KUBEVAL_VERSION=$KUBEVAL_VERSION"
echo "CIRCLE_BRANCH=$CIRCLE_BRANCH"
echo "PATH=$PATH"

echo '>> Prepare...'
mkdir -p /tmp/helm/bin
mkdir -p /tmp/helm/publish
mkdir -p /tmp/kubeval/bin
mkdir -p /tmp/kubeval/manifests

apk update
apk add ca-certificates git openssh bash curl

echo '>> Installing Helm...'
cd /tmp/helm/bin
wget "https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
tar -zxf "helm-v${HELM_VERSION}-linux-amd64.tar.gz"
chmod +x linux-amd64/helm
mv linux-amd64/helm /usr/local/bin/
helm version -c
helm init -c
helm plugin install https://github.com/lrills/helm-unittest

echo '>> Installing kubeval...'
wget https://github.com/garethr/kubeval/releases/download/${KUBEVAL_VERSION}/kubeval-linux-amd64.tar.gz 
tar xzvf kubeval-linux-amd64.tar.gz
chmod u+x kubeval
mv kubeval /usr/local/bin

echo '>> Linting charts...'
find "$HELM_CHARTS_SOURCE" -mindepth 1 -maxdepth 1 -type d | while read chart; do
  echo ">>> helm lint $chart"
  helm lint "$chart"

  echo ">>> kubeval $chart"
  mkdir -p "/tmp/kubeval/manifests/$chart_name"
  helm template $chart --output-dir "/tmp/kubeval/manifests/$chart_name"
  find "/tmp/kubeval/manifests/$chart_name" -name '*.yaml' | grep -v crd | xargs kubeval -v $KUBERNETES_VERSION  
 
  echo ">>> unittest $chart"
  /root/project/.circleci/prep-unit-tests.sh  
  helm unittest $chart 

done

