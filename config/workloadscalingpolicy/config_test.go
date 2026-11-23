package workloadscalingpolicy_test

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/crossplane/crossplane-runtime/pkg/fieldpath"

	"github.com/crossplane-contrib/crossplane-provider-castai/apis/castai/v1alpha1"
)

// Dropping these fields during generation silently changes autoscaling ownership
// and limits. Exercise the Kubernetes API to Terraform boundary, including false
// and zero values that must survive serialization.
func TestNativeHPAParameters(t *testing.T) {
	const settings = `[{"managementOption":"MANAGED","takeOwnership":false,
  "nativeHpaSpec":[{"minReplicas":3,"maxReplicas":25,
    "metrics":[{"type":"RESOURCE","resource":[{"name":"cpu","target":[{"type":"UTILIZATION","value":"70"}]}]},
      {"type":"RESOURCE","resource":[{"name":"memory","target":[{"type":"UTILIZATION","value":"70"}]}]}],
    "behavior":[{"scaleUp":[{"stabilizationWindowSeconds":0,"selectPolicy":"MAX_CHANGE_POLICY_SELECT","policies":[{"type":"PERCENT_SCALING_POLICY","value":100,"periodSeconds":60}]}],
      "scaleDown":[{"stabilizationWindowSeconds":300,"selectPolicy":"MIN_CHANGE_POLICY_SELECT","policies":[{"type":"PODS_SCALING_POLICY","value":1,"periodSeconds":60}]}]}]}]}]`
	const terraformSettings = `[{"management_option":"MANAGED","take_ownership":false,
  "native_hpa_spec":[{"min_replicas":3,"max_replicas":25,
    "metrics":[{"type":"RESOURCE","resource":[{"name":"cpu","target":[{"type":"UTILIZATION","value":"70"}]}]},
      {"type":"RESOURCE","resource":[{"name":"memory","target":[{"type":"UTILIZATION","value":"70"}]}]}],
    "behavior":[{"scale_up":[{"stabilization_window_seconds":0,"select_policy":"MAX_CHANGE_POLICY_SELECT","policies":[{"type":"PERCENT_SCALING_POLICY","value":100,"period_seconds":60}]}],
      "scale_down":[{"stabilization_window_seconds":300,"select_policy":"MIN_CHANGE_POLICY_SELECT","policies":[{"type":"PODS_SCALING_POLICY","value":1,"period_seconds":60}]}]}]}]}]`
	var want any
	if err := json.Unmarshal([]byte(terraformSettings), &want); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"forProvider", "initProvider"} {
		t.Run(field, func(t *testing.T) {
			var policy v1alpha1.ScalingPolicy
			if err := json.Unmarshal([]byte(`{"spec":{"`+field+`":{"hpaSettings":`+settings+`}}}`), &policy); err != nil {
				t.Fatal(err)
			}
			parameters, err := policy.GetMergedParameters(true)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(parameters["hpa_settings"], want) {
				t.Fatalf("native HPA settings lost or changed: got %#v, want %#v", parameters["hpa_settings"], want)
			}
			if err := policy.SetObservation(parameters); err != nil {
				t.Fatal(err)
			}
			observation, err := policy.GetObservation()
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(observation["hpa_settings"], want) {
				t.Fatalf("observed native HPA settings lost or changed: got %#v", observation["hpa_settings"])
			}
		})
	}
}

// An omitted scale-down window sends 300 s, so adopting a policy whose
// observed window is 0 must keep the 0 instead of dropping it as empty.
func TestLateInitializationKeepsZeroScaleDownWindow(t *testing.T) {
	for _, tc := range []struct {
		window string
		want   any
	}{
		{window: `"stabilization_window_seconds":0,`, want: float64(0)},
		{window: ``, want: nil},
	} {
		var policy v1alpha1.ScalingPolicy
		observation := `{"hpa_settings":[{"management_option":"MANAGED","native_hpa_spec":[{"min_replicas":1,"max_replicas":2,
  "behavior":[{"scale_down":[{` + tc.window + `"select_policy":"MAX_CHANGE_POLICY_SELECT"}]}]}]}]}`
		if _, err := policy.LateInitialize([]byte(observation)); err != nil {
			t.Fatal(err)
		}
		parameters, err := policy.GetParameters()
		if err != nil {
			t.Fatal(err)
		}
		const path = "hpa_settings[0].native_hpa_spec[0].behavior[0].scale_down[0].stabilization_window_seconds"
		window, err := fieldpath.Pave(parameters).GetValue(path)
		if err != nil && !fieldpath.IsNotFound(err) {
			t.Fatal(err)
		}
		if window != tc.want {
			t.Errorf("late-initialized scale-down window = %v, want %v", window, tc.want)
		}
	}
}
