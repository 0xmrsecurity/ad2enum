import requests
import urllib3
from bs4 import BeautifulSoup, Comment
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys
import json
import argparse

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class HiddenCommentExtractor:
    def __init__(self):
        self.session = requests.Session()
        self.headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'}

    def extract(self, url_list):
        if isinstance(url_list, str): url_list = [url_list]
        results = []
        print(f"[*] Scanning {len(url_list)} target(s)...\n")

        # Single thread or Multi-thread depending on size
        workers = 5 if len(url_list) > 1 else 1
        
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(self._scan, u) for u in url_list]
            for future in as_completed(futures):
                res = future.result()
                results.append(res)
                self._print_status(res)
                
        return results

    def _scan(self, url):
        try:
            r = self.session.get(url, headers=self.headers, timeout=15, verify=False)
            soup = BeautifulSoup(r.content, 'lxml')
            
            # Extract only HTML comments
            comments = [c.strip() for c in soup.find_all(string=lambda t: isinstance(t, Comment)) if c.strip()]
            
            return {"url": url, "status": "ok", "count": len(comments), "data": comments}
        except Exception as e:
            return {"url": url, "status": "fail", "error": str(e)}

    def _print_status(self, res):
        status_icon = "[+]" if res["status"] == "ok" else "[-]"
        msg = f"{res.get('count', 0)} comments" if res["status"]=="ok" else res.get("error")
        print(f"{status_icon} {res['url']} -> {msg}")

# ====================== CLI INTERFACE ======================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Hidden Comment Dumper v2")
    parser.add_argument('target', nargs='*', help="URL(s)")
    parser.add_argument('-f', '--file', help="File list of URLs")
    args = parser.parse_args()

    targets = []
    if args.file:
        with open(args.file) as f: targets = [l.strip() for l in f if l.strip()]
    elif args.target:
        targets = args.target
    
    if not targets:
        sys.exit("No targets provided.")

    tool = HiddenCommentExtractor()
    results = tool.extract(targets)

    # ================= FULL DETAILED OUTPUT =================
    print("\n" + "="*60 + " RAW CONTENT DUMP " + "="*60)
    
    for r in results:
        if r['status'] == 'ok' and r['data']:
            print(f"\n🔗 Target: {r['url']}")
            print("-"*60)
            
            # Print every comment found fully
            for idx, comment in enumerate(r['data'], 1):
                # Replace newlines with literal \n or print as block? 
                # We use .replace to keep it readable on one line or pretty print block:
                print(f"\n--- COMMENT #{idx} ---")
                print(comment) 
                # Note: Using print(comment) allows real newlines to format naturally
            
            print("-"*60)

    # Auto-save
    with open("found_comments.json", "w") as f:
        json.dump(results, f, indent=4, default=str)
    print("\n[✓] Data saved to found_comments.json")
