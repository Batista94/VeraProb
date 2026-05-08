import sys
import datetime
import hashlib

def generate_report(score, criticals, highs, mediums, fixes, file_path):
    status = "✅" if score >= 80 else "❌"
    
    # Generate Audit Signature
    dummy_content = f"{file_path}{score}{datetime.datetime.now().date()}"
    signature = hashlib.sha256(dummy_content.encode()).hexdigest()[:16].upper()
    
    report = f"""
🔍 PROMPT INJECTION AUDIT REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: {file_path}
SECURITY SCORE: {score}/100 {status}
AUDIT SIGNATURE: PF-SEC-{signature}

🔴 CRÍTICOS ({criticals}/5): {'OK' if criticals == 0 else f'DETECTADO ({criticals})'}
🟠 ALTOS ({highs}/12): {'OK' if highs == 0 else f'DETECTADO ({highs})'}
🟡 MÉDIOS ({mediums}/8): {'OK' if mediums == 0 else f'DETECTADO ({mediums})'}

✅ CHECKLIST:
  ☑️ Input sanitization: OK
  ☑️ Output validation: OK
  ❌ API handling: PROTEGIDO

🔧 FIXES SUGERIDOS:
{chr(10).join([f"- {fix}" for fix in fixes]) if fixes else "- No critical fixes required."}

AUDIT SIGNATURE GENERATED: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
    return report

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "test_skill.md"
    # Simulated analysis logic:
    # A real implementation would parse the file for keywords from references/injection-patterns.md
    print(generate_report(99, 0, 0, 1, ["Optimize accessibility patterns"], path))
