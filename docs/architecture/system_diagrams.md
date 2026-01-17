# 📊 System Diagrams

This document visualizes the core structural and deployment views of the Quoodle system.

## 1. System Context (Container View)

This high-level view shows how the five main components interact to form the Quoodle platform.

```mermaid
C4Context
    title System Context Diagram - Quoodle Platform

    Person(user, "Mobile User", "Administrator managing devices via Quoodle App")
    
    System_Boundary(quoodle_cloud, "Quoodle Cloud Environment") {
        Container(mobile, "quoodle-mobile-client", "Flutter", "User interface for pairing and control")
        Container(control, "quoodle-control-plane", "Laravel", "Auth, Policy, CA, Audit Log")
        Container(gateway, "quoodle-gateway", "FastAPI", "Real-time WSS Hub")
    }

    System_Boundary(device, "Target Device (Windows)") {
        Container(agent, "quoodle-agent-windows", "C++ (User Mode)", "WSS Client, Signature Verification")
        Container(kernel, "quoodle-kernel-guard", "C/C++ (Kernel)", "Privileged Execution, Anti-Tamper")
    }

    Rel(user, mobile, "Uses")
    Rel(mobile, control, "HTTPS (API)", "Commands, Auth")
    Rel(mobile, gateway, "WSS / Push", "Telemetry, Alerts")
    
    Rel(control, gateway, "HTTP/Webhook", "Dispatch, Presence")
    
    Rel(agent, gateway, "WSS (mTLS)", "Command Channel")
    Rel(agent, kernel, "IOCTL", "Execution")
```

---

## 2. Network & Deployment View

```mermaid
graph TB
    subgraph Internet
        Mobile[quoodle-mobile-client]
    end

    subgraph "Cloud / Data Center"
        LB[Load Balancer]
        
        subgraph "Control Zone"
            Control[quoodle-control-plane]
            DB[(MySQL)]
            Redis[(Redis)]
        end
        
        subgraph "Real-time Zone"
            Gateway[quoodle-gateway]
        end
        
        LB --> Control
        LB --> Gateway
        
        Control -.->|Read/Write| DB
        Gateway -.->|Stream| Redis
        Control -.->|Enqueue| Redis
    end

    subgraph "Customer Premise / Public Internet"
        subgraph "Windows Device"
            Agent[quoodle-agent-windows]
            Kernel[quoodle-kernel-guard]
        end
    end

    Mobile -->|HTTPS/443| LB
    Agent -->|WSS/443| LB
    Agent <--> Kernel
```
