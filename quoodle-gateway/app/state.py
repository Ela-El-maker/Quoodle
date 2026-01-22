from app.ws.connection_manager import ConnectionManager
from app.services.policy_resolver import PolicyResolver
from app.services.quarantine_handler import QuarantineHandler
from app.services.offline_queue import OfflineQueue
from app.services.ota_manager import OTAManager
from app.services.risk_scorer import RiskScorer
from app.services.eventbus import EventBus
from app.services.presence_tracker import PresenceTracker
from app.services.webhook_outbox import WebhookOutbox, OutboxConfig
from app.config import settings

# Shared singletons
manager = ConnectionManager()
policy_resolver = PolicyResolver()
quarantine_handler = QuarantineHandler()
offline_queue = OfflineQueue(max_per_device=200)
ota_manager = OTAManager()
risk_scorer = RiskScorer()
eventbus = EventBus()
presence = PresenceTracker()
webhook_outbox = WebhookOutbox(
    OutboxConfig(
        db_path=settings.webhook_outbox_db_path,
        max_attempts=settings.webhook_outbox_max_attempts,
        base_delay_seconds=settings.webhook_outbox_base_delay_seconds,
        max_delay_seconds=settings.webhook_outbox_max_delay_seconds,
        worker_interval_seconds=settings.webhook_outbox_worker_interval_seconds,
    )
)

# Legacy alias
event_bus = eventbus
