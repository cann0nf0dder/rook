Rook 1.0+ is being deployed in single rook-ceph namespace by default
Clusters created in v0.8 or v0.9 used rook-ceph-system and rook-ceph
I've provided the files in this dir to create 1.0+ rook deployment and maintain the split for the couple namespaces

This is useful to be able to deploy new rook clusters with the same configuration as upgraded clusters running in production (until we can migrate to single namespace / align it)

To deploy run:
kubectl apply -f ./rook-ceph-namespace.yaml (to create that namespace)
kubectl apply -f ./common.yaml

Follow the rest of the process as per rook documentation
https://rook.io/docs/rook/v1.1/ 
