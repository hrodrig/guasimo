# 02-helm-chart-with-values-and-templates.md

## Prompt

Design (not fully implement) a Helm chart called `web-api` for a
containerised HTTP service. The chart must:

1. Default to 2 replicas.
2. Allow overriding the image tag, replica count, and a single env var
   `LOG_LEVEL` from `values.yaml`.
3. Use a `Deployment`, a `Service` (ClusterIP), and an
   `HorizontalPodAutoscaler` (min 2, max 10, target CPU 70%).
4. Have a NOTES.txt that prints the URL where the service is reachable
   inside the cluster (`http://web-api.<namespace>.svc.cluster.local:80/`).
5. Use a helper template `_helpers.tpl` for the standard labels
   (`app.kubernetes.io/name`, `app.kubernetes.io/instance`,
   `app.kubernetes.io/managed-by`).

## Acceptance

- [ ] `Chart.yaml` has `apiVersion: v2`, name, version (0.1.0),
      appVersion, type `application`.
- [ ] `values.yaml` has `replicaCount`, `image.repository`,
      `image.tag`, `image.pullPolicy`, `service.port`,
      `autoscaling.minReplicas`, `autoscaling.maxReplicas`,
      `autoscaling.targetCPUUtilizationPercentage`, `env.LOG_LEVEL`.
- [ ] `templates/deployment.yaml` uses `{{ .Values.replicaCount }}`,
      `{{ .Values.image.repository }}:{{ .Values.image.tag | default
      .Chart.AppVersion }}`, and `{{- include "web-api.selectorLabels"
      . | nindent 6 }}` for labels.
- [ ] `templates/service.yaml` uses `ClusterIP`, named port `http`,
      targetPort 8080.
- [ ] `templates/hpa.yaml` uses `autoscaling/v2`.
- [ ] `templates/_helpers.tpl` defines `web-api.name`,
      `web-api.fullname`, `web-api.selectorLabels`,
      `web-api.labels`.
- [ ] `templates/NOTES.txt` is plain text with the FQDN rendered.
- [ ] No `latest` tag used.
- [ ] No resources requests/limits set in defaults (the operator should
      configure those).

## Difficulty

Medium. Tests Helm template idioms.