# postgres.txt should be formatted as:
# username=your_username
# password=your_password
# port=5432
# database=your_database


#Create function to extract credentials
def read_credentials(file_path):
    credentials ={}  #create a dictionary==
    with open(file_path, 'r') as f:
        for line in f:
            key, value = line.strip().split('=')
            credentials[key] = value
    
    return credentials

#Run function
credentials = read_credentials('postgres.txt')

username = credentials['username']
password = credentials['password']
port = int(credentials['port'])
database = credentials['database']

