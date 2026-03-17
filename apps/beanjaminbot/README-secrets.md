# beanJAMinBOT Secrets

The bot credentials are stored as a Kubernetes Secret, not in git.

## Create the Secret

Copy your `botjamin_auth.yaml` from the beanJAMinBOT repo's `config/` directory:

    kubectl create secret generic beanjaminbot-auth \
      --from-file=botjamin_auth.yaml=/path/to/your/botjamin_auth.yaml

## Verify

    kubectl get secret beanjaminbot-auth
    kubectl describe secret beanjaminbot-auth

## Update

To update credentials, delete and recreate:

    kubectl delete secret beanjaminbot-auth
    kubectl create secret generic beanjaminbot-auth \
      --from-file=botjamin_auth.yaml=/path/to/your/botjamin_auth.yaml

Then restart the pod:

    kubectl rollout restart deployment beanjaminbot
