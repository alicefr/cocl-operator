package policy
import rego.v1

default allow := false

allow if {
  input["submods"]["cpu0"]["ear.status"] == "affirming"
  input["submods"]["cpu0"]["ear.veraison.annotated-evidence"]["tpm"]
}

allow if {
    input["submods"]["cpu0"]["ear.status"] == "affirming"
    input["submods"]["cpu1"]["ear.status"] == "affirming"
    input["submods"]["cpu1"]["ear.veraison.annotated-evidence"]["tpm"]
    input["submods"]["cpu0"]["ear.veraison.annotated-evidence"]["snp"]
}
