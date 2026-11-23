package config_test

import (
	"encoding/json"
	"testing"

	"github.com/crossplane-contrib/crossplane-provider-castai/apis/castai/v1alpha1"
)

func TestLateInitializationPreservesOmittedSettings(t *testing.T) {
	for _, tc := range []struct {
		name     string
		resource interface {
			LateInitialize([]byte) (bool, error)
			GetParameters() (map[string]any, error)
		}
		spec        string
		observation string
		omitted     []string
	}{
		{
			name:        "credentials do not acquire conflicting impersonation settings",
			resource:    &v1alpha1.GkeCluster{},
			spec:        `{"spec":{"forProvider":{"credentialsJsonSecretRef":{"name":"gcp-credentials","namespace":"default","key":"credentials"}}}}`,
			observation: `{"target_service_account_email":"target@example.invalid","castai_service_account_email":"delegate@example.invalid"}`,
			omitted:     []string{"target_service_account_email", "castai_service_account_email"},
		},
		{
			name:        "omitted networking mode remains externally managed",
			resource:    &v1alpha1.NodeTemplate{},
			spec:        `{"spec":{"forProvider":{}}}`,
			observation: `{"clm_networking_mode":"tc"}`,
			omitted:     []string{"clm_networking_mode"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := json.Unmarshal([]byte(tc.spec), tc.resource); err != nil {
				t.Fatal(err)
			}
			if _, err := tc.resource.LateInitialize([]byte(tc.observation)); err != nil {
				t.Fatal(err)
			}
			parameters, err := tc.resource.GetParameters()
			if err != nil {
				t.Fatal(err)
			}
			for _, key := range tc.omitted {
				if _, present := parameters[key]; present {
					t.Errorf("late initialization took ownership of omitted setting %s", key)
				}
			}
		})
	}
}
