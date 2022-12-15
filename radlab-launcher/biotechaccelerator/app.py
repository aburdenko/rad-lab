from flask import Flask, render_template
import subprocess
app = Flask(__name__)

from turbo_flask import Turbo
turbo = Turbo(app)

app.config['TEMPLATES_AUTO_RELOAD'] = True

#CMD_TEMPLATE : str ="python /home/aburdenko/rad-lab/radlab-launcher/radlab.py --module MODULE --action 'Create New' --rad-project kallogjeri-project-345114 --rad-bucket radlab" 
CMD_TEMPLATE : str = "/home/aburdenko/rad-lab/radlab-launcher/biotechaccelerator/run_cmd.sh"

__output = None
stdout = None
stderr = None


import threading
import asyncio

import time


def update_load():
    with app.app_context():
        while True:
            time.sleep(5)
            turbo.push(turbo.replace(render_template('messages.html'), 'ds_output'))

@app.before_first_request
def before_first_request():
    threading.Thread(target=update_load).start()

@app.route('/')
def home():
   return render_template('./main.html')


async def run(cmd):
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE)

    stdout, stderr = await proc.communicate()

    print(f'[{cmd!r} exited with {proc.returncode}]')
    
    if stdout:
        print(f'[stdout]\n{stdout.decode()}')
    if stderr:
        print(f'[stderr]\n{stderr.decode()}')



def run_command(cmd):     
    import subprocess
    import shlex
    import sys
    import io

    proc = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE)
 
 
        # proc=subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell = True)
        # while True:
        #     out = process.stdout.read(1)
        #     if out == '' and process.poll() != None:
        #         break
        #     if out != '':
        #         sys.stdout.write(f)
        #         sys.stdout.flush()    
    
    f = open("output.txt", "w")
    f.close()

    # Writing data to a file
    
    for line in io.TextIOWrapper(proc.stdout, encoding="utf-8"): 
        if line == '' and proc.poll() is not None:
            break
        if line:
            str1 = line.rstrip().lstrip().replace("[0m","")
            #print( str1 )
            with open("output.txt", "a") as file1:                                                
                file1.writelines( str1 )            
                file1.writelines('\n')            
        

    # while True:
    #     output = process.stdout.readline()            
    #     if output == '' and process.poll() is not None:
    #         break
    #     if output:                          
    #         # Writing data to a file
    #         with open("output.txt", "a") as file1:                    
    #             file1.writelines(str(output.strip()).replace("0m'b'", '<br/>'))            
    rc = proc.poll()    
    return rc


@app.route('/alphafold')
def alpha_fold():
   module='alpha_fold'
   cmd = CMD_TEMPLATE.replace( 'MODULE', module )   
   
   run_command(cmd)
   send_email('Biotech Accelerator Automated Message', 'Biotech Accelerator Installed Alphafold2 in your project.')

   
   return render_template('./main.html')

@app.context_processor
def inject_load():
    import sys
    import random
    import os.path
    from os import path
            
    output='INITIALIZING...'
                  

    if path.exists('output.txt'):    
        with open('output.txt', 'rt') as f:
            output = f.read()
    else:
        output = "INITIALIZING..."
    
    return {'load1': output}   

def send_email(subject, body):
    import smtplib

    gmail_user = 'REPLACE_ME'
    gmail_password = 'REPLACE_ME'

    sent_from = gmail_user
    to = ['aburdenko@google.com']
    

    email_text = """\
    From: %s
    To: %s
    Subject: %s

    %s
    """ % (sent_from, ", ".join(to), subject, body)

    server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
    server.ehlo()
    server.login(gmail_user, gmail_password)
    server.sendmail(sent_from, to, email_text)
    server.close()
    print('Email sent!')

if __name__ == '__main__':
   app.run()