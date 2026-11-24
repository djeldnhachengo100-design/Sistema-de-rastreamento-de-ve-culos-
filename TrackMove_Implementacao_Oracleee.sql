SET DEFINE OFF
SET SERVEROUTPUT ON
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT Verificacao inicial do esquema
DECLARE
  n NUMBER;
BEGIN
  IF SYS_CONTEXT('USERENV','SESSION_USER') IN ('SYS','SYSTEM') THEN
    RAISE_APPLICATION_ERROR(-20090,'Use um esquema de trabalho proprio');
  END IF;
  SELECT COUNT(*) INTO n FROM user_objects
  WHERE object_type IN
    ('TABLE','VIEW','SEQUENCE','PROCEDURE','FUNCTION','PACKAGE','TRIGGER');
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20091,'O esquema deve estar vazio');
  END IF;
END;
/


PROMPT Codigo C02
CREATE TABLE PERFIL (
  id_perfil NUMBER(10) PRIMARY KEY,
  nome VARCHAR2(50) NOT NULL UNIQUE,
  descricao VARCHAR2(200)
);

CREATE TABLE UTILIZADOR (
  id_utilizador NUMBER(10) PRIMARY KEY,
  nome VARCHAR2(120) NOT NULL,
  login VARCHAR2(60) NOT NULL UNIQUE,
  senha_hash VARCHAR2(255) NOT NULL,
  id_perfil NUMBER(10) NOT NULL REFERENCES PERFIL
);

CREATE TABLE VEICULO (
  id_veiculo NUMBER(10) PRIMARY KEY,
  matricula VARCHAR2(20) NOT NULL UNIQUE,
  marca VARCHAR2(50) NOT NULL,
  modelo VARCHAR2(50) NOT NULL,
  limite_velocidade NUMBER(5,2) NOT NULL,
  CHECK (limite_velocidade > 0)
);

CREATE TABLE MOTORISTA (
  id_motorista NUMBER(10) PRIMARY KEY,
  nome VARCHAR2(120) NOT NULL,
  contacto VARCHAR2(30) NOT NULL,
  documento VARCHAR2(40) UNIQUE
);

CREATE TABLE DISPOSITIVO_GPS (
  id_gps NUMBER(10) PRIMARY KEY,
  codigo VARCHAR2(50) NOT NULL UNIQUE,
  id_veiculo NUMBER(10) NOT NULL UNIQUE REFERENCES VEICULO,
  CONSTRAINT uq_gps_veiculo UNIQUE (id_gps,id_veiculo)
);

CREATE TABLE ALOCACAO_MOTORISTA (
  id_alocacao NUMBER(10) PRIMARY KEY,
  id_veiculo NUMBER(10) NOT NULL REFERENCES VEICULO,
  id_motorista NUMBER(10) NOT NULL REFERENCES MOTORISTA,
  data_inicio TIMESTAMP NOT NULL,
  data_fim TIMESTAMP,
  CHECK (data_fim IS NULL OR data_fim > data_inicio)
);

CREATE TABLE LOCALIZACAO (
  id_localizacao NUMBER(18) PRIMARY KEY,
  id_veiculo NUMBER(10) NOT NULL REFERENCES VEICULO,
  id_gps NUMBER(10) NOT NULL,
  latitude NUMBER(10,7) NOT NULL,
  longitude NUMBER(10,7) NOT NULL,
  velocidade NUMBER(7,2) NOT NULL,
  ignicao CHAR(1) NOT NULL,
  quilometragem NUMBER(12,2) NOT NULL,
  data_hora TIMESTAMP NOT NULL,
  CHECK (latitude BETWEEN -90 AND 90),
  CHECK (longitude BETWEEN -180 AND 180),
  CHECK (velocidade >= 0 AND quilometragem >= 0),
  CHECK (ignicao IN ('Y','N')),
  CONSTRAINT fk_loc_gps FOREIGN KEY (id_gps,id_veiculo)
    REFERENCES DISPOSITIVO_GPS (id_gps,id_veiculo),
  CONSTRAINT uq_loc_tempo UNIQUE (id_veiculo,data_hora),
  CONSTRAINT uq_loc_veiculo UNIQUE (id_localizacao,id_veiculo)
);

CREATE TABLE ZONA_GEOFENCING (
  id_zona NUMBER(10) PRIMARY KEY,
  nome VARCHAR2(100) NOT NULL,
  definicao_geografica CLOB NOT NULL,
  limite_paragem NUMBER(10,2),
  CHECK (definicao_geografica IS JSON),
  CHECK (limite_paragem IS NULL OR limite_paragem > 0)
);

CREATE TABLE VEICULO_ZONA (
  id_veiculo NUMBER(10) REFERENCES VEICULO,
  id_zona NUMBER(10) REFERENCES ZONA_GEOFENCING,
  data_inicio TIMESTAMP NOT NULL,
  data_fim TIMESTAMP,
  PRIMARY KEY (id_veiculo,id_zona),
  CHECK (data_fim IS NULL OR data_fim > data_inicio)
);

CREATE TABLE EVENTO_VELOCIDADE (
  id_evento_vel NUMBER(18) PRIMARY KEY,
  id_veiculo NUMBER(10) NOT NULL REFERENCES VEICULO,
  id_motorista NUMBER(10) NOT NULL REFERENCES MOTORISTA,
  id_localizacao NUMBER(18) NOT NULL UNIQUE,
  velocidade NUMBER(7,2) NOT NULL CHECK (velocidade >= 0),
  data_hora TIMESTAMP NOT NULL,
  FOREIGN KEY (id_localizacao,id_veiculo)
    REFERENCES LOCALIZACAO (id_localizacao,id_veiculo)
);

CREATE TABLE EVENTO_PARAGEM (
  id_evento_paragem NUMBER(18) PRIMARY KEY,
  id_veiculo NUMBER(10) NOT NULL REFERENCES VEICULO,
  id_motorista NUMBER(10) NOT NULL REFERENCES MOTORISTA,
  id_localizacao NUMBER(18) NOT NULL UNIQUE,
  ignicao CHAR(1) NOT NULL CHECK (ignicao IN ('Y','N')),
  duracao_min NUMBER(10,2) NOT NULL CHECK (duracao_min > 0),
  data_hora TIMESTAMP NOT NULL,
  FOREIGN KEY (id_localizacao,id_veiculo)
    REFERENCES LOCALIZACAO (id_localizacao,id_veiculo)
);

CREATE TABLE EVENTO_GEOFENCING (
  id_evento_geo NUMBER(18) PRIMARY KEY,
  id_veiculo NUMBER(10) NOT NULL REFERENCES VEICULO,
  id_zona NUMBER(10) NOT NULL REFERENCES ZONA_GEOFENCING,
  tipo_ocorrencia VARCHAR2(10) NOT NULL
    CHECK (tipo_ocorrencia IN ('ENTRADA','SAIDA')),
  data_hora TIMESTAMP NOT NULL,
  UNIQUE (id_veiculo,id_zona,data_hora)
);

CREATE TABLE NOTIFICACAO (
  id_notificacao NUMBER(18) PRIMARY KEY,
  id_utilizador NUMBER(10) NOT NULL REFERENCES UTILIZADOR,
  tipo_evento VARCHAR2(30) NOT NULL
    CHECK (tipo_evento IN ('VELOCIDADE','GEOFENCING','PARAGEM')),
  referencia_evento NUMBER(18) NOT NULL,
  data_envio TIMESTAMP NOT NULL,
  estado VARCHAR2(20) NOT NULL
    CHECK (estado IN ('REGISTADA','ENVIADA','LIDA','FALHOU')),
  UNIQUE (id_utilizador,tipo_evento,referencia_evento)
);

CREATE TABLE AUDITORIA (
  id_auditoria NUMBER(18) PRIMARY KEY,
  id_utilizador NUMBER(10) NOT NULL REFERENCES UTILIZADOR,
  operacao VARCHAR2(20) NOT NULL,
  entidade VARCHAR2(60) NOT NULL,
  id_registo NUMBER(18),
  data_hora TIMESTAMP NOT NULL,
  detalhe CLOB
);

PROMPT Codigo C03
CREATE SEQUENCE sq_perfil START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_perfil
BEFORE INSERT ON PERFIL FOR EACH ROW
BEGIN
  IF :NEW.id_perfil IS NULL THEN
    :NEW.id_perfil := sq_perfil.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_utilizador START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_utilizador
BEFORE INSERT ON UTILIZADOR FOR EACH ROW
BEGIN
  IF :NEW.id_utilizador IS NULL THEN
    :NEW.id_utilizador := sq_utilizador.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_veiculo START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_veiculo
BEFORE INSERT ON VEICULO FOR EACH ROW
BEGIN
  IF :NEW.id_veiculo IS NULL THEN
    :NEW.id_veiculo := sq_veiculo.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_motorista START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_motorista
BEFORE INSERT ON MOTORISTA FOR EACH ROW
BEGIN
  IF :NEW.id_motorista IS NULL THEN
    :NEW.id_motorista := sq_motorista.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_dispositivo_gps START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_dispositivo_gps
BEFORE INSERT ON DISPOSITIVO_GPS FOR EACH ROW
BEGIN
  IF :NEW.id_gps IS NULL THEN
    :NEW.id_gps := sq_dispositivo_gps.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_alocacao_motorista START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_alocacao_motorista
BEFORE INSERT ON ALOCACAO_MOTORISTA FOR EACH ROW
BEGIN
  IF :NEW.id_alocacao IS NULL THEN
    :NEW.id_alocacao := sq_alocacao_motorista.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_localizacao START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_localizacao
BEFORE INSERT ON LOCALIZACAO FOR EACH ROW
BEGIN
  IF :NEW.id_localizacao IS NULL THEN
    :NEW.id_localizacao := sq_localizacao.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_zona_geofencing START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_zona_geofencing
BEFORE INSERT ON ZONA_GEOFENCING FOR EACH ROW
BEGIN
  IF :NEW.id_zona IS NULL THEN
    :NEW.id_zona := sq_zona_geofencing.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_evento_velocidade START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_evento_velocidade
BEFORE INSERT ON EVENTO_VELOCIDADE FOR EACH ROW
BEGIN
  IF :NEW.id_evento_vel IS NULL THEN
    :NEW.id_evento_vel := sq_evento_velocidade.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_evento_paragem START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_evento_paragem
BEFORE INSERT ON EVENTO_PARAGEM FOR EACH ROW
BEGIN
  IF :NEW.id_evento_paragem IS NULL THEN
    :NEW.id_evento_paragem := sq_evento_paragem.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_evento_geofencing START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_evento_geofencing
BEFORE INSERT ON EVENTO_GEOFENCING FOR EACH ROW
BEGIN
  IF :NEW.id_evento_geo IS NULL THEN
    :NEW.id_evento_geo := sq_evento_geofencing.NEXTVAL;
  END IF;
END;
/

CREATE SEQUENCE sq_notificacao START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_notificacao
BEFORE INSERT ON NOTIFICACAO FOR EACH ROW
BEGIN
  IF :NEW.id_notificacao IS NULL THEN
    :NEW.id_notificacao := sq_notificacao.NEXTVAL;
  END IF;
END;
/


CREATE SEQUENCE sq_auditoria START WITH 1
  INCREMENT BY 1 CACHE 20 NOCYCLE;

CREATE OR REPLACE TRIGGER bi_auditoria
BEFORE INSERT ON AUDITORIA FOR EACH ROW
BEGIN
  IF :NEW.id_auditoria IS NULL THEN
    :NEW.id_auditoria := sq_auditoria.NEXTVAL;
  END IF;
END;
/

CREATE INDEX ix_tm_01 ON ALOCACAO_MOTORISTA (id_veiculo,data_inicio,data_fim);

CREATE INDEX ix_tm_02 ON ALOCACAO_MOTORISTA (id_motorista);

CREATE INDEX ix_tm_03 ON LOCALIZACAO (id_gps);

CREATE INDEX ix_tm_04 ON VEICULO_ZONA (id_zona);

CREATE INDEX ix_tm_05 ON EVENTO_VELOCIDADE (id_veiculo,data_hora);

CREATE INDEX ix_tm_06 ON EVENTO_PARAGEM (id_veiculo,data_hora);

CREATE INDEX ix_tm_07 ON EVENTO_GEOFENCING (id_zona,data_hora);

CREATE INDEX ix_tm_08 ON NOTIFICACAO (id_utilizador,estado);

CREATE INDEX ix_tm_09 ON AUDITORIA (id_utilizador,data_hora);

CREATE INDEX ix_tm_10 ON UTILIZADOR (id_perfil);

PROMPT Codigo C04
CREATE OR REPLACE FUNCTION fn_distancia(
  a_lat NUMBER, a_lon NUMBER, b_lat NUMBER, b_lon NUMBER
) RETURN NUMBER DETERMINISTIC IS
  r CONSTANT NUMBER := ACOS(-1)/180;
  h NUMBER;
BEGIN
  h := POWER(SIN((b_lat-a_lat)*r/2),2)
     + COS(a_lat*r)*COS(b_lat*r)
     * POWER(SIN((b_lon-a_lon)*r/2),2);
  RETURN 12742000*ASIN(SQRT(LEAST(1,GREATEST(0,h))));
END;
/
CREATE OR REPLACE TRIGGER tr_zona_valida
BEFORE INSERT OR UPDATE ON ZONA_GEOFENCING
FOR EACH ROW
DECLARE
  a NUMBER; b NUMBER; r NUMBER;
BEGIN
  SELECT JSON_VALUE(:NEW.definicao_geografica,
           '$.latitude' RETURNING NUMBER ERROR ON ERROR),
         JSON_VALUE(:NEW.definicao_geografica,
           '$.longitude' RETURNING NUMBER ERROR ON ERROR),
         JSON_VALUE(:NEW.definicao_geografica,
           '$.raio_m' RETURNING NUMBER ERROR ON ERROR)
  INTO a,b,r FROM dual;
  IF a IS NULL OR b IS NULL OR r IS NULL
     OR a NOT BETWEEN -90 AND 90
     OR b NOT BETWEEN -180 AND 180 OR r <= 0 THEN
    RAISE_APPLICATION_ERROR(-20001,'Zona circular invalida');
  END IF;
END;
/
CREATE OR REPLACE TRIGGER tr_notif_valida
BEFORE INSERT OR UPDATE ON NOTIFICACAO FOR EACH ROW
DECLARE n NUMBER := 0;
BEGIN
  IF :NEW.tipo_evento = 'VELOCIDADE' THEN
    SELECT COUNT(*) INTO n FROM EVENTO_VELOCIDADE
    WHERE id_evento_vel = :NEW.referencia_evento;
  ELSIF :NEW.tipo_evento = 'GEOFENCING' THEN
    SELECT COUNT(*) INTO n FROM EVENTO_GEOFENCING
    WHERE id_evento_geo = :NEW.referencia_evento;
  ELSIF :NEW.tipo_evento = 'PARAGEM' THEN
    SELECT COUNT(*) INTO n FROM EVENTO_PARAGEM
    WHERE id_evento_paragem = :NEW.referencia_evento;
  END IF;
  IF n = 0 THEN
    RAISE_APPLICATION_ERROR(-20002,'Evento inexistente');
  END IF;
END;
/
CREATE OR REPLACE PROCEDURE pr_notificar(
  p_tipo VARCHAR2, p_evento NUMBER
) IS
BEGIN
  INSERT INTO NOTIFICACAO
    (id_utilizador,tipo_evento,referencia_evento,
     data_envio,estado)
  SELECT u.id_utilizador,p_tipo,p_evento,
         LOCALTIMESTAMP,'REGISTADA'
  FROM UTILIZADOR u JOIN PERFIL p
    ON p.id_perfil=u.id_perfil
  WHERE p.nome='GESTOR';
END;
/

PROMPT Codigo C05
CREATE OR REPLACE PROCEDURE pr_alocar(
  p_veiculo NUMBER, p_motorista NUMBER,
  p_inicio TIMESTAMP, p_fim TIMESTAMP DEFAULT NULL
) IS
  n NUMBER;
BEGIN
  SELECT id_veiculo INTO n FROM VEICULO
  WHERE id_veiculo=p_veiculo FOR UPDATE;
  IF p_inicio IS NULL OR p_fim <= p_inicio THEN
    RAISE_APPLICATION_ERROR(-20003,'Periodo invalido');
  END IF;
  SELECT COUNT(*) INTO n FROM ALOCACAO_MOTORISTA
  WHERE id_veiculo=p_veiculo
    AND (p_fim IS NULL OR data_inicio < p_fim)
    AND (data_fim IS NULL OR data_fim > p_inicio);
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20004,'Alocacao sobreposta');
  END IF;
  INSERT INTO ALOCACAO_MOTORISTA
    (id_veiculo,id_motorista,data_inicio,data_fim)
  VALUES (p_veiculo,p_motorista,p_inicio,p_fim);
END;
/
CREATE OR REPLACE PROCEDURE pr_registar_localizacao(
  p_veiculo NUMBER, p_gps NUMBER,
  p_lat NUMBER, p_lon NUMBER, p_vel NUMBER,
  p_ign CHAR, p_km NUMBER, p_data TIMESTAMP
) IS
  v_lim NUMBER; v_motor NUMBER; v_n NUMBER;
  v_id NUMBER; v_evento NUMBER;
  v_ant LOCALIZACAO%ROWTYPE;
  v_tem_ant BOOLEAN := FALSE;
  v_inicio TIMESTAMP; v_cursor TIMESTAMP;
  v_min NUMBER; v_lim_par NUMBER := NULL;
  v_dentro BOOLEAN; v_antes BOOLEAN;
  v_tipo VARCHAR2(10);
BEGIN
  SAVEPOINT recepcao_tm;
  SELECT limite_velocidade INTO v_lim FROM VEICULO
  WHERE id_veiculo=p_veiculo FOR UPDATE;
  SELECT COUNT(*),MIN(id_motorista) INTO v_n,v_motor
  FROM ALOCACAO_MOTORISTA
  WHERE id_veiculo=p_veiculo AND data_inicio <= p_data
    AND (data_fim IS NULL OR p_data < data_fim);
  IF v_n <> 1 THEN
    RAISE_APPLICATION_ERROR(-20005,'Exige um motorista activo');
  END IF;
  BEGIN
    SELECT * INTO v_ant FROM (
      SELECT * FROM LOCALIZACAO WHERE id_veiculo=p_veiculo
      ORDER BY data_hora DESC
    ) WHERE ROWNUM=1;
    v_tem_ant := TRUE;
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;
  IF v_tem_ant THEN
    IF p_data <= v_ant.data_hora OR p_km < v_ant.quilometragem
    THEN
      RAISE_APPLICATION_ERROR(-20006,'Tempo ou km invalidos');
    END IF;
  END IF;
  INSERT INTO LOCALIZACAO
    (id_veiculo,id_gps,latitude,longitude,velocidade,
     ignicao,quilometragem,data_hora)
  VALUES (p_veiculo,p_gps,p_lat,p_lon,p_vel,p_ign,p_km,p_data)
  RETURNING id_localizacao INTO v_id;
  IF p_vel > v_lim THEN
    INSERT INTO EVENTO_VELOCIDADE
      (id_veiculo,id_motorista,id_localizacao,
       velocidade,data_hora)
    VALUES (p_veiculo,v_motor,v_id,p_vel,p_data)
    RETURNING id_evento_vel INTO v_evento;
    pr_notificar('VELOCIDADE',v_evento);
  END IF;
  FOR z IN (
    SELECT z.id_zona,z.limite_paragem,vz.data_inicio,
      JSON_VALUE(z.definicao_geografica,
        '$.latitude' RETURNING NUMBER) lat,
      JSON_VALUE(z.definicao_geografica,
        '$.longitude' RETURNING NUMBER) lon,
      JSON_VALUE(z.definicao_geografica,
        '$.raio_m' RETURNING NUMBER) raio
    FROM ZONA_GEOFENCING z JOIN VEICULO_ZONA vz
      ON vz.id_zona=z.id_zona
    WHERE vz.id_veiculo=p_veiculo
      AND vz.data_inicio <= p_data
      AND (vz.data_fim IS NULL OR p_data < vz.data_fim)
  ) LOOP
    v_dentro := fn_distancia(p_lat,p_lon,z.lat,z.lon)<=z.raio;
    IF v_dentro AND z.limite_paragem IS NOT NULL THEN
      v_lim_par := LEAST(NVL(v_lim_par,z.limite_paragem),
                         z.limite_paragem);
    END IF;
    IF v_tem_ant AND v_ant.data_hora >= z.data_inicio THEN
      v_antes := fn_distancia(v_ant.latitude,v_ant.longitude,
                             z.lat,z.lon)<=z.raio;
      IF v_dentro <> v_antes THEN
        IF v_dentro THEN v_tipo:='ENTRADA';
        ELSE v_tipo:='SAIDA'; END IF;
        INSERT INTO EVENTO_GEOFENCING
          (id_veiculo,id_zona,tipo_ocorrencia,data_hora)
        VALUES (p_veiculo,z.id_zona,v_tipo,p_data)
        RETURNING id_evento_geo INTO v_evento;
        pr_notificar('GEOFENCING',v_evento);
      END IF;
    END IF;
  END LOOP;
  IF p_ign='Y' AND p_vel<=1 THEN
    v_inicio := p_data; v_cursor := p_data;
    FOR l IN (
      SELECT * FROM LOCALIZACAO
      WHERE id_veiculo=p_veiculo AND data_hora < p_data
      ORDER BY data_hora DESC
    ) LOOP
      EXIT WHEN l.ignicao<>'Y' OR l.velocidade>1
        OR fn_distancia(p_lat,p_lon,l.latitude,l.longitude)>30
        OR v_cursor-l.data_hora > INTERVAL '5' MINUTE;
      v_inicio := l.data_hora; v_cursor := l.data_hora;
    END LOOP;
    v_min := (CAST(p_data AS DATE)-CAST(v_inicio AS DATE))*1440;
    SELECT COUNT(*) INTO v_n FROM EVENTO_PARAGEM
    WHERE id_veiculo=p_veiculo AND data_hora>=v_inicio;
    IF v_min > NVL(v_lim_par,10) AND v_n=0 THEN
      INSERT INTO EVENTO_PARAGEM
        (id_veiculo,id_motorista,id_localizacao,
         ignicao,duracao_min,data_hora)
      VALUES (p_veiculo,v_motor,v_id,'Y',v_min,p_data)
      RETURNING id_evento_paragem INTO v_evento;
      pr_notificar('PARAGEM',v_evento);
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK TO recepcao_tm;
  RAISE;
END;
/

PROMPT Codigo C06
CREATE OR REPLACE TRIGGER hist_localizacao
BEFORE UPDATE OR DELETE ON LOCALIZACAO
BEGIN
  RAISE_APPLICATION_ERROR(-20007,'Historico protegido');
END;
/

CREATE OR REPLACE TRIGGER hist_evento_velocidade
BEFORE UPDATE OR DELETE ON EVENTO_VELOCIDADE
BEGIN
  RAISE_APPLICATION_ERROR(-20007,'Historico protegido');
END;
/

CREATE OR REPLACE TRIGGER hist_evento_geofencing
BEFORE UPDATE OR DELETE ON EVENTO_GEOFENCING
BEGIN
  RAISE_APPLICATION_ERROR(-20007,'Historico protegido');
END;
/

CREATE OR REPLACE TRIGGER hist_evento_paragem
BEFORE UPDATE OR DELETE ON EVENTO_PARAGEM
BEGIN
  RAISE_APPLICATION_ERROR(-20007,'Historico protegido');
END;
/

CREATE OR REPLACE TRIGGER hist_auditoria
BEFORE UPDATE OR DELETE ON AUDITORIA
BEGIN
  RAISE_APPLICATION_ERROR(-20007,'Historico protegido');
END;
/

CREATE OR REPLACE TRIGGER tr_audita_veiculo
AFTER INSERT OR UPDATE OR DELETE ON VEICULO
FOR EACH ROW
DECLARE
  v_u NUMBER; v_op VARCHAR2(20);
BEGIN
  SELECT id_utilizador INTO v_u FROM UTILIZADOR
  WHERE login=SYS_CONTEXT('USERENV','SESSION_USER');
  IF INSERTING THEN v_op:='INSERT';
  ELSIF UPDATING THEN v_op:='UPDATE';
  ELSE v_op:='DELETE'; END IF;
  INSERT INTO AUDITORIA
    (id_utilizador,operacao,entidade,id_registo,
     data_hora,detalhe)
  VALUES (v_u,v_op,'VEICULO',
    NVL(:NEW.id_veiculo,:OLD.id_veiculo),LOCALTIMESTAMP,
    'Matricula anterior='||:OLD.matricula||
    '; nova='||:NEW.matricula||
    '; limite anterior='||:OLD.limite_velocidade||
    '; novo='||:NEW.limite_velocidade);
END;
/

PROMPT Verificacao da compilacao antes dos dados de teste
DECLARE
  n NUMBER;
BEGIN
  FOR e IN (SELECT name,line,text FROM user_errors
            WHERE attribute='ERROR' ORDER BY name,sequence) LOOP
    DBMS_OUTPUT.PUT_LINE(e.name||' linha '||e.line||': '||e.text);
  END LOOP;
  SELECT COUNT(*) INTO n FROM user_objects WHERE status='INVALID';
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20092,'Objectos invalidos: corrigir antes da carga');
  END IF;
END;
/


PROMPT Codigo C07
DECLARE
  pa NUMBER; pg NUMBER; u NUMBER;
  v1 NUMBER; v2 NUMBER; m1 NUMBER; m2 NUMBER;
  g1 NUMBER; g2 NUMBER; z NUMBER;
  t TIMESTAMP := TIMESTAMP '2026-10-16 08:00:00';
BEGIN
  INSERT INTO PERFIL (nome,descricao)
  VALUES ('ADMINISTRADOR','Administracao do sistema')
  RETURNING id_perfil INTO pa;
  INSERT INTO PERFIL (nome,descricao)
  VALUES ('GESTOR','Consulta da frota e alertas')
  RETURNING id_perfil INTO pg;
  INSERT INTO UTILIZADOR (nome,login,senha_hash,id_perfil)
  VALUES ('Conta tecnica Oracle',
    SYS_CONTEXT('USERENV','SESSION_USER'),'!BLOQUEADA!',pa);
  INSERT INTO UTILIZADOR (nome,login,senha_hash,id_perfil)
  VALUES ('Gestor de teste','gestor.demo','!BLOQUEADA!',pg);
  INSERT INTO VEICULO (matricula,marca,modelo,limite_velocidade)
  VALUES ('AAA-001-MP','Toyota','Hilux',80)
  RETURNING id_veiculo INTO v1;
  INSERT INTO VEICULO (matricula,marca,modelo,limite_velocidade)
  VALUES ('AAA-002-MP','Isuzu','NPR',70)
  RETURNING id_veiculo INTO v2;
  INSERT INTO MOTORISTA (nome,contacto,documento)
  VALUES ('Motorista Teste A','CONTACTO-TESTE-A','DOC-TESTE-A')
  RETURNING id_motorista INTO m1;
  INSERT INTO MOTORISTA (nome,contacto,documento)
  VALUES ('Motorista Teste B','CONTACTO-TESTE-B','DOC-TESTE-B')
  RETURNING id_motorista INTO m2;
  INSERT INTO DISPOSITIVO_GPS (codigo,id_veiculo)
  VALUES ('GPS-TESTE-001',v1) RETURNING id_gps INTO g1;
  INSERT INTO DISPOSITIVO_GPS (codigo,id_veiculo)
  VALUES ('GPS-TESTE-002',v2) RETURNING id_gps INTO g2;
  pr_alocar(v1,m1,t);
  pr_alocar(v2,m2,t);
  INSERT INTO ZONA_GEOFENCING
    (nome,definicao_geografica,limite_paragem)
  VALUES ('Base Maputo',
    '{"latitude":-25.965,"longitude":32.583,"raio_m":500}',10)
  RETURNING id_zona INTO z;
  INSERT INTO VEICULO_ZONA
    (id_veiculo,id_zona,data_inicio) VALUES (v1,z,t);
  pr_registar_localizacao(v1,g1,-25.965,32.583,0,'Y',1000,t);
  pr_registar_localizacao(v1,g1,-25.950,32.583,95,'Y',1002,
    t+INTERVAL '2' MINUTE);
  pr_registar_localizacao(v1,g1,-25.965,32.583,0,'Y',1004,
    t+INTERVAL '4' MINUTE);
  FOR i IN 1..3 LOOP
    pr_registar_localizacao(v1,g1,-25.965,32.583,0,'Y',1004,
      t+NUMTODSINTERVAL(4+i*4,'MINUTE'));
  END LOOP;
  pr_registar_localizacao(v2,g2,-25.970,32.580,0,'N',2000,t);
  COMMIT;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  RAISE;
END;
/

PROMPT Codigo C08
CREATE OR REPLACE VIEW vw_ultima_localizacao AS
SELECT l.id_veiculo,v.matricula,l.latitude,l.longitude,
       l.velocidade,l.ignicao,l.quilometragem,l.data_hora,
       m.nome AS motorista
FROM LOCALIZACAO l JOIN VEICULO v
  ON v.id_veiculo=l.id_veiculo
LEFT JOIN ALOCACAO_MOTORISTA a
  ON a.id_veiculo=l.id_veiculo AND a.data_inicio<=l.data_hora
  AND (a.data_fim IS NULL OR l.data_hora<a.data_fim)
LEFT JOIN MOTORISTA m ON m.id_motorista=a.id_motorista
WHERE NOT EXISTS (
  SELECT 1 FROM LOCALIZACAO x
  WHERE x.id_veiculo=l.id_veiculo AND x.data_hora>l.data_hora
);
SELECT * FROM vw_ultima_localizacao ORDER BY id_veiculo;
SELECT * FROM EVENTO_VELOCIDADE ORDER BY data_hora;
SELECT * FROM EVENTO_GEOFENCING ORDER BY data_hora;
SELECT * FROM EVENTO_PARAGEM ORDER BY data_hora;
SELECT * FROM NOTIFICACAO ORDER BY id_notificacao;
SELECT * FROM AUDITORIA ORDER BY id_auditoria;
SELECT 'LOCALIZACAO' tabela,COUNT(*) total FROM LOCALIZACAO
UNION ALL
SELECT 'VELOCIDADE',COUNT(*) FROM EVENTO_VELOCIDADE
UNION ALL
SELECT 'GEOFENCING',COUNT(*) FROM EVENTO_GEOFENCING
UNION ALL
SELECT 'PARAGEM',COUNT(*) FROM EVENTO_PARAGEM
UNION ALL
SELECT 'NOTIFICACAO',COUNT(*) FROM NOTIFICACAO
UNION ALL
SELECT 'AUDITORIA',COUNT(*) FROM AUDITORIA;
SELECT object_name,object_type,status FROM user_objects
WHERE status='INVALID';
SELECT name,type,line,position,text FROM user_errors
ORDER BY name,sequence;

PROMPT Validacao automatica do cenario
DECLARE
  n NUMBER;
  PROCEDURE verificar(p_nome VARCHAR2,p_total NUMBER,p_esperado NUMBER) IS
  BEGIN
    IF p_total <> p_esperado THEN
      RAISE_APPLICATION_ERROR(-20093,p_nome||': esperado '||
        p_esperado||', obtido '||p_total);
    END IF;
    DBMS_OUTPUT.PUT_LINE('OK - '||p_nome||': '||p_total);
  END;
BEGIN
  SELECT COUNT(*) INTO n FROM LOCALIZACAO;
  verificar('Localizacoes',n,7);
  SELECT COUNT(*) INTO n FROM EVENTO_VELOCIDADE;
  verificar('Excessos de velocidade',n,1);
  SELECT COUNT(*) INTO n FROM EVENTO_GEOFENCING;
  verificar('Eventos de geofencing',n,2);
  SELECT COUNT(*) INTO n FROM EVENTO_PARAGEM;
  verificar('Paragens prolongadas',n,1);
  SELECT COUNT(*) INTO n FROM NOTIFICACAO;
  verificar('Notificacoes',n,4);
  SELECT COUNT(*) INTO n FROM AUDITORIA;
  verificar('Registos de auditoria',n,2);
  SELECT COUNT(*) INTO n FROM user_objects WHERE status='INVALID';
  verificar('Objectos invalidos',n,0);
  DBMS_OUTPUT.PUT_LINE('TRACKMOVE: IMPLEMENTACAO E TESTES CONCLUIDOS PRLO GRUPO.');
END;
/

