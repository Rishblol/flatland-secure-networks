CREATE TABLE lab_fixture (
    id integer PRIMARY KEY,
    value text NOT NULL
);

INSERT INTO lab_fixture (id, value) VALUES (1, 'flatland-db-ok');

CREATE ROLE lab_reader LOGIN PASSWORD 'flatland-reader-demo';
GRANT SELECT ON lab_fixture TO lab_reader;
