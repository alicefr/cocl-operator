package policy

import rego.v1

default hardware := 97

## TPM validation
hardware := 3 if {
  input.tpm.pcr04 in query_reference_value("tpm_pcr4")

}

# Azure SNP vTPM validation
hardware := 3 if {
  lower(input.azsnpvtpm.tpm.pcr04) in query_reference_value("tpm_pcr4")
}

## AMD SNP
hardware := 3 if {
  input.snp.reported_tcb_snp == 28
}

default executables := 0
default configuration := 0
default file_system := 0
default instance_identity := 0
default runtime_opaque := 0
default storage_opaque := 0
default sourced_data := 0

trust_claims := {
  "executables": executables,
  "hardware": hardware,
  "configuration": configuration,
  "file-system": file_system,
  "instance-identity": instance_identity,
  "runtime-opaque": runtime_opaque,
  "storage-opaque": storage_opaque,
  "sourced-data": sourced_data,
}
