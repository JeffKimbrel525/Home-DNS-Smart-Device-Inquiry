-- Table Creations

create type device_category as enum ('IoT', 'Human Device', 'Infrastructure');

-- pi-hole query status codes with human-readable labels and result categories
create table status (
    status_id   integer primary key,
    status_name text,
    result      text,
    description text
);

insert into status (status_id, status_name, result, description) values
    (0,  'unknown',                   'n/a',       'query not yet processed'),
    (1,  'blocked (gravity)',         'blocked',   'standard ad-list hit'),
    (2,  'forwarded',                 'permitted', 'sent to upstream; key for latency tracking'),
    (3,  'cached',                    'permitted', 'speed benefit; no network traffic generated'),
    (4,  'blocked (wildcard)',        'blocked',   'regex filter match'),
    (5,  'blocked (blacklist)',       'blocked',   'exact match on personal blacklist'),
    (6,  'blocked (external ip)',     'blocked',   'upstream blocked it via ip'),
    (7,  'blocked (external null)',   'blocked',   'upstream returned 0.0.0.0'),
    (8,  'blocked (external nx)',     'blocked',   'upstream returned nxdomain'),
    (9,  'blocked (cname gravity)',   'blocked',   'blocked deep in cname chain (gravity)'),
    (10, 'blocked (cname regex)',     'blocked',   'blocked deep in cname chain (regex)'),
    (11, 'blocked (cname blacklist)', 'blocked',   'blocked deep in cname chain (blacklist)'),
    (12, 'retried',                   'permitted', 'standard retry from client'),
    (13, 'retried (ignored)',         'permitted', 'ignored to prevent loops/spam'),
    (14, 'already forwarded',         'permitted', 'duplicate query already in flight'),
    (15, 'blocked (database busy)',   'error',     'outage indicator: ftl could not write to disk'),
    (16, 'blocked (special domain)',  'blocked',   'apple private relay / mozilla canary'),
    (17, 'replied from stale cache',  'permitted', 'outage indicator: upstream was down, using old data')
;



-- raw query log, populated by the pi-hole ftl bash export script
create table dns_logs (
    id              bigint primary key, -- Using the ID from Pi-hole as our key
    timestamp       bigint,
    type            integer,
    status          integer references status(status_id),
    domain          text,
    client          text,
    forward         text,
    additional_info text,
    reply_type      integer,
    reply_time      real,
    dnssec          integer,
    list_id         integer,
    ede             integer
);


create index idx_dns_logs_client on dns_logs (client);



-- known network devices, populated by the bash mac/ip export script
create table network_devices (
    id            serial primary key,
    hwaddr        text,
    ip            inet,
    name          text,
    friendly_name text,
    last_seen     timestamp,
    device_type	  device_category,
    constraint network_devices_hwaddr_ip_unique unique (hwaddr, ip)
);


create index idx_network_devices_ip     on network_devices (ip);
create index idx_network_devices_hwaddr on network_devices (hwaddr);

/* name came from pihole where pihole received it from the device, anywhere name was not
 * populated automatically and for all friendly_names, those were manually added after
 * verification via dns records and in some cases, powering off devices and testing
 * with ping
 *
 * all devices were assigned static dhcp leases early in the life of the pihole server,
 * ensuring ip addresses remain consistent throughout the dataset. this makes ip-based
 * device identification reliable for analysis purposes.
 */


/* adding a column to identify IoT vs Human devices, and quickly skip/ignore my local infrastructure
 * and search by IoT or just Human devices.
 */

/* friendly_name was assigned manually, one device at a time, by querying
 * dns_logs for each ip and identifying the device by the domains it queried.
 * in some cases cross-referenced with dns records and the ping/power-off
 * method described in the network_devices table comment.
 */
update network_devices
set friendly_name = t.friendly_name
from (values
    ('10.10.17.53'::inet,  'Ring #1'),
    ('10.10.17.56'::inet,  'Fan #3'),
    ('10.10.17.60'::inet,  'Smart Lock'),
    ('10.10.17.79'::inet,  'Oven'),
    ('10.10.17.80'::inet,  'Fan #1'),
    ('10.10.17.88'::inet,  'Ecobee'),
    ('10.10.17.89'::inet,  'Fan #2'),
    ('10.10.17.104'::inet, 'Digital Photo Frame'),
    ('10.10.17.106'::inet, 'Echo Show'),
    ('10.10.17.108'::inet, '3D-Printer'),
    ('10.10.17.109'::inet, 'Meater Block'),
    ('10.10.17.129'::inet, 'Traeger Grill'),
    ('10.10.17.143'::inet, 'Ring #2'),
    ('10.10.17.146'::inet, 'Smart Plug'),
    ('10.10.17.157'::inet, 'Echo Dot'),
    ('10.10.17.161'::inet, 'Garage Door Opener'),
    ('10.10.17.165'::inet, 'Ring #3'),
    ('10.10.17.173'::inet, 'espressif.lan'),
    ('10.10.17.183'::inet, 'Smart Switch'),
    ('10.10.17.184'::inet, 'Sprinkler Controller'),
    ('10.10.17.186'::inet, 'Blink Camera'),
    ('10.10.17.194'::inet, 'Robot Vacuum')
) as t(ip, friendly_name)
where network_devices.ip = t.ip
;


-- for my local servers, router etc
update network_devices nd 
set device_type = 'Infrastructure' 
where ip in (
	'10.10.17.1',
	'10.10.17.2',
	'10.10.17.3',
	'10.10.17.4',
	'10.10.17.5',
	'10.10.17.12',
	'10.10.17.52',
	'10.10.17.59',
	'10.10.17.110',
	'10.10.17.164',
	'127.0.0.1'
)
;

-- for iphones, pc's, tablets etc.
update network_devices nd
set device_type = 'Human Device' 
where ip in (
    '10.10.17.11',
    '10.10.17.55',
    '10.10.17.66',
    '10.10.17.77',
    '10.10.17.85',
    '10.10.17.86',
    '10.10.17.87',
    '10.10.17.93',
    '10.10.17.99',
    '10.10.17.100',
    '10.10.17.113',
    '10.10.17.121',
    '10.10.17.137',
    '10.10.17.140',
    '10.10.17.144',
    '10.10.17.148',
    '10.10.17.160',
    '10.10.17.166',
    '10.10.17.175',
    '10.10.17.192',
    '10.10.17.195',
    '10.10.17.196',
    '10.10.17.197',
    '10.137.3.2',
    '10.137.3.4'
)
;

/* IoT or internet of things, these are all the smart devices on the network and will be
the main focus of my project */
update network_devices nd
set device_type = 'IoT' 
where ip in (
    '10.10.17.53',
    '10.10.17.56',
    '10.10.17.60',
    '10.10.17.79',
    '10.10.17.80',
    '10.10.17.88',
    '10.10.17.89',
    '10.10.17.90',
    '10.10.17.97',
    '10.10.17.104',
    '10.10.17.106',
    '10.10.17.108',
    '10.10.17.109',
    '10.10.17.129',
    '10.10.17.143',
    '10.10.17.145',
    '10.10.17.146',
    '10.10.17.157',
    '10.10.17.161',
    '10.10.17.165',
    '10.10.17.173',
    '10.10.17.179',
    '10.10.17.183',
    '10.10.17.184',
    '10.10.17.186',
	'10.10.17.188',
	'10.10.17.191',
    '10.10.17.194'
)
;

