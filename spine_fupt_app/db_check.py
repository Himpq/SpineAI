import sqlite3
conn = sqlite3.connect(r'D:\HealthIT\spine\code\Spine_FUPT\spine_workbench.db')
c = conn.cursor()
c.execute("SELECT * FROM wb_users")
cols = [d[0] for d in c.description]
print("Columns:", cols)
for row in c.fetchall():
    d = dict(zip(cols, row))
    # Don't print password hash
    d.pop('password_hash', None)
    print(d)
conn.close()
