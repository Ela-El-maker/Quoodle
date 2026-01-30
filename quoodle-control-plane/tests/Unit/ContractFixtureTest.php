<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

class ContractFixtureTest extends TestCase
{
    private function fixture(string $name): array
    {
        $path = __DIR__ . '/../fixtures/contracts/' . $name;
        $this->assertFileExists($path, "Missing fixture: {$name}");
        $json = file_get_contents($path);
        $this->assertNotFalse($json, "Failed to read fixture: {$name}");
        $data = json_decode($json, true);
        $this->assertIsArray($data, "Fixture not valid JSON: {$name}");
        return $data;
    }

    /** @test */
    public function it_keeps_state_vocab_in_sync(): void
    {
        $vocab = $this->fixture('state_vocab.json');
        $this->assertContains('online', $vocab['device_states']);
        $this->assertContains('queued', $vocab['command_states']);
        $this->assertContains('compliant', $vocab['compliance_states']);
    }

    /** @test */
    public function it_validates_mobile_contract_fixtures(): void
    {
        $deviceList = $this->fixture('mobile_device_list.json');
        $this->assertArrayHasKey('devices', $deviceList);
        $this->assertArrayHasKey('device_id', $deviceList['devices'][0]);
        $this->assertArrayHasKey('lifecycle_state', $deviceList['devices'][0]);

        $deviceDetail = $this->fixture('mobile_device_detail.json');
        $this->assertArrayHasKey('device_id', $deviceDetail);
        $this->assertArrayHasKey('compliance', $deviceDetail);
        $this->assertArrayHasKey('telemetry_latest', $deviceDetail);

        $commandDetail = $this->fixture('mobile_command_detail.json');
        $this->assertArrayHasKey('command_id', $commandDetail);
        $this->assertArrayHasKey('state', $commandDetail);
        $this->assertArrayHasKey('result', $commandDetail);

        $commandList = $this->fixture('mobile_command_list.json');
        $this->assertArrayHasKey('commands', $commandList);
        $this->assertArrayHasKey('command_id', $commandList['commands'][0]);
        $this->assertArrayHasKey('state', $commandList['commands'][0]);

        $alerts = $this->fixture('mobile_alerts.json');
        $this->assertArrayHasKey('alerts', $alerts);
        $this->assertArrayHasKey('alert_id', $alerts['alerts'][0]);

        $telemetry = $this->fixture('mobile_telemetry_history.json');
        $this->assertArrayHasKey('device_id', $telemetry);
        $this->assertArrayHasKey('points', $telemetry);
        $this->assertArrayHasKey('avg_cpu', $telemetry['points'][0]);

        $updates = $this->fixture('mobile_updates_list.json');
        $this->assertArrayHasKey('updates', $updates);
        $this->assertArrayHasKey('release_id', $updates['updates'][0]);

        $updateDetail = $this->fixture('mobile_update_detail.json');
        $this->assertArrayHasKey('release_id', $updateDetail);
        $this->assertArrayHasKey('progress', $updateDetail);

        $audit = $this->fixture('mobile_audit_chain.json');
        $this->assertArrayHasKey('entries', $audit);
        $this->assertArrayHasKey('id', $audit['entries'][0]);

        $policy = $this->fixture('mobile_policy_evaluate.json');
        $this->assertArrayHasKey('decision', $policy);
    }

    /** @test */
    public function it_validates_gateway_contract_fixtures(): void
    {
        $dispatch = $this->fixture('gateway_dispatch.json');
        $this->assertArrayHasKey('command_id', $dispatch);
        $this->assertArrayHasKey('policy', $dispatch);
        $this->assertArrayHasKey('envelope', $dispatch);

        $ack = $this->fixture('gateway_webhook_ack.json');
        $this->assertArrayHasKey('command_id', $ack);
        $this->assertArrayHasKey('status', $ack);

        $result = $this->fixture('gateway_webhook_result.json');
        $this->assertArrayHasKey('command_id', $result);
        $this->assertArrayHasKey('execution_state', $result);
        $this->assertArrayHasKey('result', $result);

        $online = $this->fixture('gateway_webhook_device_online.json');
        $this->assertArrayHasKey('device_id', $online);
        $this->assertArrayHasKey('session_id', $online);
    }
}
