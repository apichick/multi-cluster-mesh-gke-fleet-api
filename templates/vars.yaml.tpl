istio_version: ${istio_version}
clusters:
%{ for key, cluster in clusters ~}
  - name: ${key}
    region: ${cluster.region}
%{ endfor ~}    
service_account_email: ${service_account_email}
project_id: ${project_id}