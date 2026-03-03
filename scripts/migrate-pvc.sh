#!/bin/bash
set -e

usage() {
  echo "Usage: $0 -p <pvc-name> -s <storage-size> [-n <namespace>] [-c <temp-storageclass>]"
  echo ""
  echo "  -p  Name of the PVC to migrate (required)"
  echo "  -s  Storage size for the temp PVC, e.g. 5Gi (required)"
  echo "  -n  Namespace (default: default)"
  echo "  -c  StorageClass for the temp PVC (default: local-path)"
  exit 1
}

NAMESPACE="default"
TEMP_STORAGECLASS="local-path"

while getopts "p:s:n:c:" opt; do
  case $opt in
    p) PVC_NAME="$OPTARG" ;;
    s) STORAGE_SIZE="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    c) TEMP_STORAGECLASS="$OPTARG" ;;
    *) usage ;;
  esac
done

if [ -z "$PVC_NAME" ] || [ -z "$STORAGE_SIZE" ]; then
  usage
fi

TEMP_PVC="${PVC_NAME}-temp"

echo "==> Migrating PVC '$PVC_NAME' in namespace '$NAMESPACE'"
echo "    Temp PVC: $TEMP_PVC (StorageClass: $TEMP_STORAGECLASS, Size: $STORAGE_SIZE)"
echo ""

echo "==> Creating temp PVC '$TEMP_PVC'..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEMP_PVC
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $TEMP_STORAGECLASS
  resources:
    requests:
      storage: $STORAGE_SIZE
EOF

echo "==> Copying '$PVC_NAME' to '$TEMP_PVC'..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-pvc-to-temp
  namespace: $NAMESPACE
spec:
  ttlSecondsAfterFinished: 60
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: copy
        image: alpine:latest
        command: ["sh", "-c", "cp -av /source/. /dest/"]
        volumeMounts:
        - name: source
          mountPath: /source
        - name: dest
          mountPath: /dest
      volumes:
      - name: source
        persistentVolumeClaim:
          claimName: $PVC_NAME
      - name: dest
        persistentVolumeClaim:
          claimName: $TEMP_PVC
EOF

kubectl wait --for=condition=complete job/migrate-pvc-to-temp -n "$NAMESPACE" --timeout=300s
kubectl delete job migrate-pvc-to-temp -n "$NAMESPACE" --ignore-not-found
echo "==> Copy to temp complete."

echo "==> Deleting old PVC '$PVC_NAME'..."
kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE"

echo ""
echo "==> Old PVC deleted. Please apply the new PVC manifest now, then press Enter to continue."
read -r

echo "==> Waiting for '$PVC_NAME' to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/"$PVC_NAME" -n "$NAMESPACE" --timeout=120s

echo "==> Copying '$TEMP_PVC' to '$PVC_NAME'..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-pvc-from-temp
  namespace: $NAMESPACE
spec:
  ttlSecondsAfterFinished: 60
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: copy
        image: alpine:latest
        command: ["sh", "-c", "cp -av /source/. /dest/"]
        volumeMounts:
        - name: source
          mountPath: /source
        - name: dest
          mountPath: /dest
      volumes:
      - name: source
        persistentVolumeClaim:
          claimName: $TEMP_PVC
      - name: dest
        persistentVolumeClaim:
          claimName: $PVC_NAME
EOF

kubectl wait --for=condition=complete job/migrate-pvc-from-temp -n "$NAMESPACE" --timeout=300s
kubectl delete job migrate-pvc-from-temp -n "$NAMESPACE" --ignore-not-found
echo "==> Copy from temp complete."

echo "==> Deleting temp PVC '$TEMP_PVC'..."
kubectl delete pvc "$TEMP_PVC" -n "$NAMESPACE"

echo ""
echo "==> Migration complete. You can now scale your workload back up."
