# SNI-based routing from nginx-ingress → per-broker ClusterIP Services.
#
# When the Kafka CR's external listener has externalAccess.type=staticForHostBasedRouting,
# CFK creates one internal ClusterIP Service per broker named `kafka-N-internal:9092`.
# Each Ingress rule here maps a broker hostname to its corresponding internal Service.
#
# One Ingress per nginx controller class (A, B, C). Rules are identical — each nginx
# controller independently serves the same SNI routing table, so any NLB can route to
# any broker. OMB's DNS round-robins across all 3 NLBs for load spreading.
#
# ssl-passthrough: true tells nginx NOT to terminate TLS — it reads the SNI cleartext
# from the ClientHello and forwards raw bytes. mTLS terminates at the broker, which
# sees the client cert and extracts the CN as principal (unchanged from the direct path).

# ────────────────────────────────────────────────────────────────────────────────
# nginx-zone-a Ingress (served by nginx-ingress controller in us-east-1a)
# ────────────────────────────────────────────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-sni-zone-a
  namespace: __NAMESPACE__
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  ingressClassName: nginx-zone-a
  rules:
    - host: bootstrap-ext.__DOMAIN__
      http: &rule_bootstrap
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-0-internal
                port: {number: 9092}
    - {host: b0.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-0-internal,  port: {number: 9092}}}}]}}
    - {host: b1.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-1-internal,  port: {number: 9092}}}}]}}
    - {host: b2.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-2-internal,  port: {number: 9092}}}}]}}
    - {host: b3.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-3-internal,  port: {number: 9092}}}}]}}
    - {host: b4.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-4-internal,  port: {number: 9092}}}}]}}
    - {host: b5.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-5-internal,  port: {number: 9092}}}}]}}
    - {host: b6.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-6-internal,  port: {number: 9092}}}}]}}
    - {host: b7.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-7-internal,  port: {number: 9092}}}}]}}
    - {host: b8.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-8-internal,  port: {number: 9092}}}}]}}
    - {host: b9.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-9-internal,  port: {number: 9092}}}}]}}
    - {host: b10.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-10-internal, port: {number: 9092}}}}]}}
    - {host: b11.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-11-internal, port: {number: 9092}}}}]}}
    - {host: b12.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-12-internal, port: {number: 9092}}}}]}}
    - {host: b13.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-13-internal, port: {number: 9092}}}}]}}
    - {host: b14.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-14-internal, port: {number: 9092}}}}]}}

---
# ────────────────────────────────────────────────────────────────────────────────
# nginx-zone-b Ingress (served by nginx-ingress controller in us-east-1b)
# ────────────────────────────────────────────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-sni-zone-b
  namespace: __NAMESPACE__
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  ingressClassName: nginx-zone-b
  rules:
    - {host: bootstrap-ext.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-0-internal,  port: {number: 9092}}}}]}}
    - {host: b0.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-0-internal,  port: {number: 9092}}}}]}}
    - {host: b1.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-1-internal,  port: {number: 9092}}}}]}}
    - {host: b2.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-2-internal,  port: {number: 9092}}}}]}}
    - {host: b3.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-3-internal,  port: {number: 9092}}}}]}}
    - {host: b4.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-4-internal,  port: {number: 9092}}}}]}}
    - {host: b5.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-5-internal,  port: {number: 9092}}}}]}}
    - {host: b6.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-6-internal,  port: {number: 9092}}}}]}}
    - {host: b7.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-7-internal,  port: {number: 9092}}}}]}}
    - {host: b8.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-8-internal,  port: {number: 9092}}}}]}}
    - {host: b9.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-9-internal,  port: {number: 9092}}}}]}}
    - {host: b10.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-10-internal, port: {number: 9092}}}}]}}
    - {host: b11.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-11-internal, port: {number: 9092}}}}]}}
    - {host: b12.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-12-internal, port: {number: 9092}}}}]}}
    - {host: b13.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-13-internal, port: {number: 9092}}}}]}}
    - {host: b14.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-14-internal, port: {number: 9092}}}}]}}

---
# ────────────────────────────────────────────────────────────────────────────────
# nginx-zone-c Ingress (served by nginx-ingress controller in us-east-1c)
# ────────────────────────────────────────────────────────────────────────────────
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-sni-zone-c
  namespace: __NAMESPACE__
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  ingressClassName: nginx-zone-c
  rules:
    - {host: bootstrap-ext.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-0-internal,  port: {number: 9092}}}}]}}
    - {host: b0.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-0-internal,  port: {number: 9092}}}}]}}
    - {host: b1.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-1-internal,  port: {number: 9092}}}}]}}
    - {host: b2.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-2-internal,  port: {number: 9092}}}}]}}
    - {host: b3.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-3-internal,  port: {number: 9092}}}}]}}
    - {host: b4.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-4-internal,  port: {number: 9092}}}}]}}
    - {host: b5.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-5-internal,  port: {number: 9092}}}}]}}
    - {host: b6.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-6-internal,  port: {number: 9092}}}}]}}
    - {host: b7.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-7-internal,  port: {number: 9092}}}}]}}
    - {host: b8.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-8-internal,  port: {number: 9092}}}}]}}
    - {host: b9.__DOMAIN__,  http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-9-internal,  port: {number: 9092}}}}]}}
    - {host: b10.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-10-internal, port: {number: 9092}}}}]}}
    - {host: b11.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-11-internal, port: {number: 9092}}}}]}}
    - {host: b12.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-12-internal, port: {number: 9092}}}}]}}
    - {host: b13.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-13-internal, port: {number: 9092}}}}]}}
    - {host: b14.__DOMAIN__, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: kafka-14-internal, port: {number: 9092}}}}]}}
