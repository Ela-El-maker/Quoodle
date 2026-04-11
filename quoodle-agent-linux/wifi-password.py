import subprocess
import re


def run_cmd(command):
    result = subprocess.run(command, capture_output=True, text=True, shell=True)
    return result.stdout or ""


def get_saved_profiles():
    output = run_cmd("netsh wlan show profiles")
    profiles = []

    # English Windows output: "All User Profile     : <SSID>"
    for line in output.splitlines():
        if "All User Profile" in line:
            parts = line.split(":", 1)
            if len(parts) == 2:
                ssid = parts[1].strip()
                if ssid:
                    profiles.append(ssid)

    return profiles


def get_password_for_profile(ssid):
    output = run_cmd(f'netsh wlan show profile name="{ssid}" key=clear')

    # English Windows output: "Key Content            : <password>"
    match = re.search(r"Key Content\s*:\s*(.*)", output)
    if match:
        return match.group(1).strip()

    return "(no saved password or open network)"


def main():
    profiles = get_saved_profiles()

    if not profiles:
        print("No saved Wi-Fi profiles found.")
        return

    print("Saved Wi-Fi networks and passwords:\n")
    for ssid in profiles:
        password = get_password_for_profile(ssid)
        print(f"SSID: {ssid}")
        print(f"Password: {password}")
        print("-" * 40)


if __name__ == "__main__":
    main()
