PGDMP                         z            tea_management_updated    14.3    14.3 H    i           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false            j           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false            k           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false            l           1262    17210    tea_management_updated    DATABASE     z   CREATE DATABASE tea_management_updated WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United States.1252';
 &   DROP DATABASE tea_management_updated;
                postgres    false            ?            1255    17212    mix_blendsheet()    FUNCTION     )  CREATE FUNCTION public.mix_blendsheet() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    row_exists boolean;
    bag_count integer;
BEGIN
	SELECT exists(
		SELECT 1 FROM tealine
		WHERE item_code = NEW.tealine_code
	) INTO row_exists;
	
	IF not(row_exists) THEN
		RAISE foreign_key_violation
		USING MESSAGE = format(
			'Cannot find reference with `tealine_code` = %s.',
			NEW.tealine_code
		);
	END IF;
    
    SELECT sum(t.no_of_bags) - sum(bm.no_of_bags)
    FROM tealine t INNER JOIN blendsheet_mix bm
    ON t.item_code = bm.tealine_code
    GROUP BY t.item_code
    HAVING t.item_code = NEW.tealine_code
    INTO bag_count;
        
    IF bag_count < NEW.no_of_bags THEN
        RAISE check_violation
        USING MESSAGE = 'Bag count exceeds limit.';
    END IF;
    RETURN NEW; 
END;$$;
 '   DROP FUNCTION public.mix_blendsheet();
       public          postgres    false            ?            1255    17213    mix_flavorsheet()    FUNCTION     *  CREATE FUNCTION public.mix_flavorsheet() RETURNS trigger
    LANGUAGE plpgsql
    AS $$DECLARE
    row_exists boolean;
    bag_count integer;
BEGIN
	SELECT exists(
		SELECT 1 FROM tealine
		WHERE item_code = NEW.tealine_code
	) INTO row_exists;
	
	IF not(row_exists) THEN
		RAISE foreign_key_violation
		USING MESSAGE = format(
			'Cannot find reference with `tealine_code` = %s.',
			NEW.tealine_code
		);
	END IF;
    
    SELECT sum(t.no_of_bags) - sum(bm.no_of_bags)
    FROM tealine t INNER JOIN blendsheet_mix bm
    ON t.item_code = bm.tealine_code
    GROUP BY t.item_code
    HAVING t.item_code = NEW.tealine_code
    INTO bag_count;
        
    IF bag_count < NEW.no_of_bags THEN
        RAISE check_violation
        USING MESSAGE = 'Bag count exceeds limit.';
    END IF;
    RETURN NEW; 
END;$$;
 (   DROP FUNCTION public.mix_flavorsheet();
       public          postgres    false            ?            1255    17214    record_location()    FUNCTION       CREATE FUNCTION public.record_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	is_herbline boolean := TG_ARGV[0]::boolean;
	row_exists boolean;
BEGIN
	SELECT exists(
		SELECT 1 FROM store_location
		WHERE location_name = NEW.store_location
		AND herbline_section = is_herbline
	) INTO row_exists;
	
	IF not(row_exists) THEN
		RAISE foreign_key_violation
		USING MESSAGE = format(
			'Cannot find reference with `herbline_section` = %s.',
			is_herbline::text
		);
	END IF;
	RETURN NEW;
END;
$$;
 (   DROP FUNCTION public.record_location();
       public          postgres    false            ?            1255    17215    record_status()    FUNCTION     ?   CREATE FUNCTION public.record_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    NEW.status := 'ACCEPTED';
    NEW.remaining := NEW.gross_weight - NEW.bag_weight;
    RETURN NEW;
END;$$;
 &   DROP FUNCTION public.record_status();
       public          postgres    false            ?            1255    17216    record_tealine()    FUNCTION     /  CREATE FUNCTION public.record_tealine() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	max_bag_count tealine.no_of_bags%TYPE;
	bag_count tealine.no_of_bags%TYPE;
BEGIN
	SELECT no_of_bags
	FROM tealine
	WHERE item_code = NEW.item_code
	AND created_ts = NEW.created_ts
	INTO max_bag_count;
	
	SELECT count(*)
	FROM tealine_record
	WHERE item_code = NEW.item_code
	AND created_ts = NEW.created_ts
	INTO bag_count;
	
	IF bag_count >= max_bag_count THEN
		RAISE check_violation
		USING MESSAGE = 'Bag count exceeds limit.';
	END IF;
	RETURN NEW;
END;
$$;
 '   DROP FUNCTION public.record_tealine();
       public          postgres    false            ?            1255    17217    scan_record(text, uuid)    FUNCTION     h  CREATE FUNCTION public.scan_record(tname text, barcode uuid) RETURNS json
    LANGUAGE plpgsql
    AS $$DECLARE
    record_tname text;
    record_tname_exists boolean;
    join_columns text[];
    row_result json;
BEGIN
    record_tname := tname || '_record';
    
    EXECUTE format(
      'SELECT EXISTS (' ||
      '    SELECT 1 FROM information_schema.tables ' ||
      '    WHERE table_schema = %L AND table_type = %L ' ||
      '    AND table_name = %L' ||
      ')',
      'public',
      'BASE TABLE',
      record_tname
    )
    INTO record_tname_exists;
    
    IF record_tname_exists IS false THEN
        RAISE undefined_table
        USING message = format(
          'Cannot find barcode while %L does not exist.',
          record_tname
        );
    END IF;
    
    EXECUTE format(
      'SELECT array_agg(column_name) ' ||
      'FROM information_schema.columns ' ||
      'WHERE table_schema = %L AND table_name = %L ' ||
      'AND column_name = ANY(%L)',
      'public',
       tname,
      '{item_code,created_ts}'
    )
    INTO join_columns;
    
    EXECUTE format(
      'WITH jtbl AS ' ||
      '(SELECT * FROM %s INNER JOIN %s USING(%s)) ' ||
      'SELECT json_agg(jtbl) FROM jtbl WHERE barcode = %L;',
      tname,
      record_tname,
      array_to_string(join_columns, ', '),
      barcode
    ) 
    INTO row_result;
    RETURN row_result;
END;$$;
 <   DROP FUNCTION public.scan_record(tname text, barcode uuid);
       public          postgres    false            ?            1259    17218 
   blendsheet    TABLE     R  CREATE TABLE public.blendsheet (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    blendsheet_no text NOT NULL,
    standard text NOT NULL,
    grade text NOT NULL,
    remarks text NOT NULL,
    no_of_batches integer NOT NULL,
    batches_completed integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT false NOT NULL
);
    DROP TABLE public.blendsheet;
       public         heap    postgres    false            ?            1259    17225    blendsheet_mix    TABLE     ?   CREATE TABLE public.blendsheet_mix (
    blendsheet_no text NOT NULL,
    tealine_code text NOT NULL,
    no_of_bags integer NOT NULL
);
 "   DROP TABLE public.blendsheet_mix;
       public         heap    postgres    false            ?            1259    17230    blendsheet_record    TABLE     %  CREATE TABLE public.blendsheet_record (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    received_ts bigint DEFAULT (date_part('epoch'::text, now()) * (1000)::double precision) NOT NULL,
    store_location text NOT NULL,
    bag_weight double precision NOT NULL,
    gross_weight double precision NOT NULL,
    barcode uuid DEFAULT gen_random_uuid() NOT NULL,
    status text NOT NULL,
    remaining double precision NOT NULL,
    CONSTRAINT check_254 CHECK ((status = ANY ('{ACCEPTED,PROCESSING,PROCESSED,DISPATCHED}'::text[])))
);
 %   DROP TABLE public.blendsheet_record;
       public         heap    postgres    false            ?            1259    17238    flavorsheet    TABLE     T  CREATE TABLE public.flavorsheet (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    flavorsheet_no text NOT NULL,
    standard text NOT NULL,
    grade text NOT NULL,
    remarks text NOT NULL,
    no_of_batches integer NOT NULL,
    batches_completed integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT false NOT NULL
);
    DROP TABLE public.flavorsheet;
       public         heap    postgres    false            ?            1259    17245    flavorsheet_mix    TABLE     ?   CREATE TABLE public.flavorsheet_mix (
    flavorsheet_no text NOT NULL,
    blendsheet_code text NOT NULL,
    no_of_bags integer NOT NULL
);
 #   DROP TABLE public.flavorsheet_mix;
       public         heap    postgres    false            ?            1259    17250    flavorsheet_record    TABLE     ;  CREATE TABLE public.flavorsheet_record (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    store_location text NOT NULL,
    gross_weight double precision NOT NULL,
    reference text NOT NULL,
    barcode uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'ACCEPTED'::text NOT NULL
);
 &   DROP TABLE public.flavorsheet_record;
       public         heap    postgres    false            ?            1259    17257    herbline    TABLE     V   CREATE TABLE public.herbline (
    item_code text NOT NULL,
    name text NOT NULL
);
    DROP TABLE public.herbline;
       public         heap    postgres    false            ?            1259    17262    herbline_record    TABLE     8  CREATE TABLE public.herbline_record (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    store_location text NOT NULL,
    gross_weight double precision NOT NULL,
    reference text NOT NULL,
    barcode uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'ACCEPTED'::text NOT NULL
);
 #   DROP TABLE public.herbline_record;
       public         heap    postgres    false            ?            1259    17269    item    TABLE     ?   CREATE TABLE public.item (
    item_code text NOT NULL,
    created_ts bigint DEFAULT (date_part('epoch'::text, now()) * (1000)::double precision) NOT NULL
);
    DROP TABLE public.item;
       public         heap    postgres    false            ?            1259    17275    store_location    TABLE     }   CREATE TABLE public.store_location (
    location_name text NOT NULL,
    herbline_section boolean DEFAULT false NOT NULL
);
 "   DROP TABLE public.store_location;
       public         heap    postgres    false            ?            1259    17281    tealine    TABLE       CREATE TABLE public.tealine (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    invoice_no text NOT NULL,
    grade text NOT NULL,
    no_of_bags integer NOT NULL,
    weight_per_bag double precision NOT NULL,
    broker text NOT NULL,
    garden text NOT NULL
);
    DROP TABLE public.tealine;
       public         heap    postgres    false            ?            1259    17286    tealine_record    TABLE     ?  CREATE TABLE public.tealine_record (
    item_code text NOT NULL,
    created_ts bigint NOT NULL,
    received_ts bigint DEFAULT (date_part('epoch'::text, now()) * (1000)::double precision) NOT NULL,
    store_location text NOT NULL,
    bag_weight double precision NOT NULL,
    gross_weight double precision NOT NULL,
    barcode uuid DEFAULT gen_random_uuid() NOT NULL,
    status text NOT NULL,
    remaining double precision NOT NULL
);
 "   DROP TABLE public.tealine_record;
       public         heap    postgres    false            [          0    17218 
   blendsheet 
   TABLE DATA           ?   COPY public.blendsheet (item_code, created_ts, blendsheet_no, standard, grade, remarks, no_of_batches, batches_completed, active) FROM stdin;
    public          postgres    false    209   ?m       \          0    17225    blendsheet_mix 
   TABLE DATA           Q   COPY public.blendsheet_mix (blendsheet_no, tealine_code, no_of_bags) FROM stdin;
    public          postgres    false    210   Jn       ]          0    17230    blendsheet_record 
   TABLE DATA           ?   COPY public.blendsheet_record (item_code, created_ts, received_ts, store_location, bag_weight, gross_weight, barcode, status, remaining) FROM stdin;
    public          postgres    false    211   ~n       ^          0    17238    flavorsheet 
   TABLE DATA           ?   COPY public.flavorsheet (item_code, created_ts, flavorsheet_no, standard, grade, remarks, no_of_batches, batches_completed, active) FROM stdin;
    public          postgres    false    212   ^p       _          0    17245    flavorsheet_mix 
   TABLE DATA           V   COPY public.flavorsheet_mix (flavorsheet_no, blendsheet_code, no_of_bags) FROM stdin;
    public          postgres    false    213   {p       `          0    17250    flavorsheet_record 
   TABLE DATA           }   COPY public.flavorsheet_record (item_code, created_ts, store_location, gross_weight, reference, barcode, status) FROM stdin;
    public          postgres    false    214   ?p       a          0    17257    herbline 
   TABLE DATA           3   COPY public.herbline (item_code, name) FROM stdin;
    public          postgres    false    215   ?p       b          0    17262    herbline_record 
   TABLE DATA           z   COPY public.herbline_record (item_code, created_ts, store_location, gross_weight, reference, barcode, status) FROM stdin;
    public          postgres    false    216   ?p       c          0    17269    item 
   TABLE DATA           5   COPY public.item (item_code, created_ts) FROM stdin;
    public          postgres    false    217   ?q       d          0    17275    store_location 
   TABLE DATA           I   COPY public.store_location (location_name, herbline_section) FROM stdin;
    public          postgres    false    218   r       e          0    17281    tealine 
   TABLE DATA           w   COPY public.tealine (item_code, created_ts, invoice_no, grade, no_of_bags, weight_per_bag, broker, garden) FROM stdin;
    public          postgres    false    219   Ar       f          0    17286    tealine_record 
   TABLE DATA           ?   COPY public.tealine_record (item_code, created_ts, received_ts, store_location, bag_weight, gross_weight, barcode, status, remaining) FROM stdin;
    public          postgres    false    220    s       ?           2606    17294 %   blendsheet_record blendsheet_bag_pkey 
   CONSTRAINT     h   ALTER TABLE ONLY public.blendsheet_record
    ADD CONSTRAINT blendsheet_bag_pkey PRIMARY KEY (barcode);
 O   ALTER TABLE ONLY public.blendsheet_record DROP CONSTRAINT blendsheet_bag_pkey;
       public            postgres    false    211            ?           2606    17295    blendsheet blendsheet_check    CHECK CONSTRAINT     ?   ALTER TABLE public.blendsheet
    ADD CONSTRAINT blendsheet_check CHECK (((batches_completed >= 0) AND (batches_completed <= no_of_batches))) NOT VALID;
 @   ALTER TABLE public.blendsheet DROP CONSTRAINT blendsheet_check;
       public          postgres    false    209    209    209    209            ?           2606    17296 .   blendsheet_mix blendsheet_mix_no_of_bags_check    CHECK CONSTRAINT     y   ALTER TABLE public.blendsheet_mix
    ADD CONSTRAINT blendsheet_mix_no_of_bags_check CHECK ((no_of_bags > 0)) NOT VALID;
 S   ALTER TABLE public.blendsheet_mix DROP CONSTRAINT blendsheet_mix_no_of_bags_check;
       public          postgres    false    210    210            ?           2606    17298 "   blendsheet_mix blendsheet_mix_pkey 
   CONSTRAINT     y   ALTER TABLE ONLY public.blendsheet_mix
    ADD CONSTRAINT blendsheet_mix_pkey PRIMARY KEY (blendsheet_no, tealine_code);
 L   ALTER TABLE ONLY public.blendsheet_mix DROP CONSTRAINT blendsheet_mix_pkey;
       public            postgres    false    210    210            ?           2606    17299    tealine_record check_23    CHECK CONSTRAINT     p  ALTER TABLE public.tealine_record
    ADD CONSTRAINT check_23 CHECK (
CASE
    WHEN (status = ANY ('{ACCEPTED,DISPATCHED}'::text[])) THEN (remaining = (gross_weight - bag_weight))
    WHEN (status = 'PROCESSED'::text) THEN (remaining = (0)::double precision)
    ELSE ((remaining > (0)::double precision) AND (remaining < (gross_weight - bag_weight)))
END) NOT VALID;
 <   ALTER TABLE public.tealine_record DROP CONSTRAINT check_23;
       public          postgres    false    220    220    220    220    220    220    220    220            ?           2606    17300    tealine_record check_52    CHECK CONSTRAINT     ?   ALTER TABLE public.tealine_record
    ADD CONSTRAINT check_52 CHECK ((status = ANY ('{ACCEPTED,IN_PROCESS,PROCESSED,DISPATCHED}'::text[]))) NOT VALID;
 <   ALTER TABLE public.tealine_record DROP CONSTRAINT check_52;
       public          postgres    false    220    220            ?           2606    17302 *   flavorsheet flavorsheet_flavorsheet_no_key 
   CONSTRAINT     o   ALTER TABLE ONLY public.flavorsheet
    ADD CONSTRAINT flavorsheet_flavorsheet_no_key UNIQUE (flavorsheet_no);
 T   ALTER TABLE ONLY public.flavorsheet DROP CONSTRAINT flavorsheet_flavorsheet_no_key;
       public            postgres    false    212            ?           2606    17304 $   flavorsheet_mix flavorsheet_mix_pkey 
   CONSTRAINT        ALTER TABLE ONLY public.flavorsheet_mix
    ADD CONSTRAINT flavorsheet_mix_pkey PRIMARY KEY (flavorsheet_no, blendsheet_code);
 N   ALTER TABLE ONLY public.flavorsheet_mix DROP CONSTRAINT flavorsheet_mix_pkey;
       public            postgres    false    213    213            ?           2606    17306    flavorsheet flavorsheet_pkey 
   CONSTRAINT     m   ALTER TABLE ONLY public.flavorsheet
    ADD CONSTRAINT flavorsheet_pkey PRIMARY KEY (item_code, created_ts);
 F   ALTER TABLE ONLY public.flavorsheet DROP CONSTRAINT flavorsheet_pkey;
       public            postgres    false    212    212            ?           2606    17308    herbline herbline_detail_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.herbline
    ADD CONSTRAINT herbline_detail_pkey PRIMARY KEY (item_code);
 G   ALTER TABLE ONLY public.herbline DROP CONSTRAINT herbline_detail_pkey;
       public            postgres    false    215            ?           2606    17310 $   herbline_record herbline_record_pkey 
   CONSTRAINT     g   ALTER TABLE ONLY public.herbline_record
    ADD CONSTRAINT herbline_record_pkey PRIMARY KEY (barcode);
 N   ALTER TABLE ONLY public.herbline_record DROP CONSTRAINT herbline_record_pkey;
       public            postgres    false    216            ?           2606    17312    blendsheet index_161 
   CONSTRAINT     X   ALTER TABLE ONLY public.blendsheet
    ADD CONSTRAINT index_161 UNIQUE (blendsheet_no);
 >   ALTER TABLE ONLY public.blendsheet DROP CONSTRAINT index_161;
       public            postgres    false    209            ?           2606    17314    blendsheet_record index_332 
   CONSTRAINT     Y   ALTER TABLE ONLY public.blendsheet_record
    ADD CONSTRAINT index_332 UNIQUE (barcode);
 E   ALTER TABLE ONLY public.blendsheet_record DROP CONSTRAINT index_332;
       public            postgres    false    211            ?           2606    17316    item pk_278 
   CONSTRAINT     \   ALTER TABLE ONLY public.item
    ADD CONSTRAINT pk_278 PRIMARY KEY (item_code, created_ts);
 5   ALTER TABLE ONLY public.item DROP CONSTRAINT pk_278;
       public            postgres    false    217    217            ?           2606    17318    store_location pk_35 
   CONSTRAINT     ]   ALTER TABLE ONLY public.store_location
    ADD CONSTRAINT pk_35 PRIMARY KEY (location_name);
 >   ALTER TABLE ONLY public.store_location DROP CONSTRAINT pk_35;
       public            postgres    false    218            ?           2606    17320    tealine pk_5 
   CONSTRAINT     ]   ALTER TABLE ONLY public.tealine
    ADD CONSTRAINT pk_5 PRIMARY KEY (item_code, created_ts);
 6   ALTER TABLE ONLY public.tealine DROP CONSTRAINT pk_5;
       public            postgres    false    219    219            ?           2606    17322    blendsheet pk_62 
   CONSTRAINT     a   ALTER TABLE ONLY public.blendsheet
    ADD CONSTRAINT pk_62 PRIMARY KEY (item_code, created_ts);
 :   ALTER TABLE ONLY public.blendsheet DROP CONSTRAINT pk_62;
       public            postgres    false    209    209            ?           2606    17324    tealine_record tealine_bag_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.tealine_record
    ADD CONSTRAINT tealine_bag_pkey PRIMARY KEY (barcode);
 I   ALTER TABLE ONLY public.tealine_record DROP CONSTRAINT tealine_bag_pkey;
       public            postgres    false    220            ?           1259    17325    fk_108    INDEX     N   CREATE INDEX fk_108 ON public.blendsheet_record USING btree (store_location);
    DROP INDEX public.fk_108;
       public            postgres    false    211            ?           1259    17326    fk_111    INDEX     K   CREATE INDEX fk_111 ON public.tealine_record USING btree (store_location);
    DROP INDEX public.fk_111;
       public            postgres    false    220            ?           1259    17327    fk_25    INDEX     Q   CREATE INDEX fk_25 ON public.tealine_record USING btree (item_code, created_ts);
    DROP INDEX public.fk_25;
       public            postgres    false    220    220            ?           1259    17328    fk_283    INDEX     N   CREATE INDEX fk_283 ON public.blendsheet USING btree (item_code, created_ts);
    DROP INDEX public.fk_283;
       public            postgres    false    209    209            ?           1259    17329    fk_287    INDEX     K   CREATE INDEX fk_287 ON public.tealine USING btree (item_code, created_ts);
    DROP INDEX public.fk_287;
       public            postgres    false    219    219            ?           1259    17330    fk_94    INDEX     T   CREATE INDEX fk_94 ON public.blendsheet_record USING btree (item_code, created_ts);
    DROP INDEX public.fk_94;
       public            postgres    false    211    211            ?           2620    17331     blendsheet_mix tg_mix_blendsheet    TRIGGER        CREATE TRIGGER tg_mix_blendsheet BEFORE INSERT ON public.blendsheet_mix FOR EACH ROW EXECUTE FUNCTION public.mix_blendsheet();
 9   DROP TRIGGER tg_mix_blendsheet ON public.blendsheet_mix;
       public          postgres    false    210    232            ?           2620    17332 $   blendsheet_record tg_record_location    TRIGGER     ?   CREATE TRIGGER tg_record_location BEFORE INSERT OR UPDATE OF store_location ON public.blendsheet_record FOR EACH ROW EXECUTE FUNCTION public.record_location('false');
 =   DROP TRIGGER tg_record_location ON public.blendsheet_record;
       public          postgres    false    211    234    211            ?           2620    17333 "   herbline_record tg_record_location    TRIGGER     ?   CREATE TRIGGER tg_record_location BEFORE INSERT OR UPDATE OF store_location ON public.herbline_record FOR EACH ROW EXECUTE FUNCTION public.record_location('true');
 ;   DROP TRIGGER tg_record_location ON public.herbline_record;
       public          postgres    false    216    234    216            ?           2620    17334 !   tealine_record tg_record_location    TRIGGER     ?   CREATE TRIGGER tg_record_location BEFORE INSERT OR UPDATE OF store_location ON public.tealine_record FOR EACH ROW EXECUTE FUNCTION public.record_location('false');
 :   DROP TRIGGER tg_record_location ON public.tealine_record;
       public          postgres    false    234    220    220            ?           2620    17335 "   blendsheet_record tg_record_status    TRIGGER     ?   CREATE TRIGGER tg_record_status BEFORE INSERT ON public.blendsheet_record FOR EACH ROW EXECUTE FUNCTION public.record_status();
 ;   DROP TRIGGER tg_record_status ON public.blendsheet_record;
       public          postgres    false    211    235            ?           2620    17336    tealine_record tg_record_status    TRIGGER     }   CREATE TRIGGER tg_record_status BEFORE INSERT ON public.tealine_record FOR EACH ROW EXECUTE FUNCTION public.record_status();
 8   DROP TRIGGER tg_record_status ON public.tealine_record;
       public          postgres    false    220    235            ?           2620    17337     tealine_record tg_record_tealine    TRIGGER        CREATE TRIGGER tg_record_tealine BEFORE INSERT ON public.tealine_record FOR EACH ROW EXECUTE FUNCTION public.record_tealine();
 9   DROP TRIGGER tg_record_tealine ON public.tealine_record;
       public          postgres    false    236    220            ?           2606    17338 0   blendsheet_mix blendsheet_mix_blendsheet_no_fkey    FK CONSTRAINT     ?   ALTER TABLE ONLY public.blendsheet_mix
    ADD CONSTRAINT blendsheet_mix_blendsheet_no_fkey FOREIGN KEY (blendsheet_no) REFERENCES public.blendsheet(blendsheet_no) NOT VALID;
 Z   ALTER TABLE ONLY public.blendsheet_mix DROP CONSTRAINT blendsheet_mix_blendsheet_no_fkey;
       public          postgres    false    3234    209    210            ?           2606    17343    tealine_record fk_23    FK CONSTRAINT     ?   ALTER TABLE ONLY public.tealine_record
    ADD CONSTRAINT fk_23 FOREIGN KEY (item_code, created_ts) REFERENCES public.tealine(item_code, created_ts);
 >   ALTER TABLE ONLY public.tealine_record DROP CONSTRAINT fk_23;
       public          postgres    false    219    220    220    3261    219            ?           2606    17348    herbline_record fk_231    FK CONSTRAINT     ?   ALTER TABLE ONLY public.herbline_record
    ADD CONSTRAINT fk_231 FOREIGN KEY (item_code, created_ts) REFERENCES public.item(item_code, created_ts);
 @   ALTER TABLE ONLY public.herbline_record DROP CONSTRAINT fk_231;
       public          postgres    false    216    3256    217    217    216            ?           2606    17353    blendsheet fk_280    FK CONSTRAINT     ?   ALTER TABLE ONLY public.blendsheet
    ADD CONSTRAINT fk_280 FOREIGN KEY (item_code, created_ts) REFERENCES public.item(item_code, created_ts);
 ;   ALTER TABLE ONLY public.blendsheet DROP CONSTRAINT fk_280;
       public          postgres    false    209    3256    217    217    209            ?           2606    17358    tealine fk_284    FK CONSTRAINT     ?   ALTER TABLE ONLY public.tealine
    ADD CONSTRAINT fk_284 FOREIGN KEY (item_code, created_ts) REFERENCES public.item(item_code, created_ts);
 8   ALTER TABLE ONLY public.tealine DROP CONSTRAINT fk_284;
       public          postgres    false    219    3256    219    217    217            ?           2606    17363    blendsheet_record fk_92    FK CONSTRAINT     ?   ALTER TABLE ONLY public.blendsheet_record
    ADD CONSTRAINT fk_92 FOREIGN KEY (item_code, created_ts) REFERENCES public.blendsheet(item_code, created_ts);
 A   ALTER TABLE ONLY public.blendsheet_record DROP CONSTRAINT fk_92;
       public          postgres    false    211    209    209    3236    211            ?           2606    17368 3   flavorsheet_mix flavorsheet_mix_flavorsheet_no_fkey    FK CONSTRAINT     ?   ALTER TABLE ONLY public.flavorsheet_mix
    ADD CONSTRAINT flavorsheet_mix_flavorsheet_no_fkey FOREIGN KEY (flavorsheet_no) REFERENCES public.flavorsheet(flavorsheet_no) NOT VALID;
 ]   ALTER TABLE ONLY public.flavorsheet_mix DROP CONSTRAINT flavorsheet_mix_flavorsheet_no_fkey;
       public          postgres    false    212    213    3246            [   =   x?s222010?4435?4?41?0?0?t
?7202?K?q:r????r?pr?q??qqq <?
?      \   $   x?s
?7202?7010?12204????????? P??      ]   ?  x?????!Fk????2??.RR?L?0???_E??mf?	?u???3*R?fҭ??E{??"?????;?Z?(L5????6?cvО??܀|?"#??(????~???^?Z?x?ݒ???J?.??7???5P???{k;???{ݐ???h???Z??'B??m,8)??? ?m??ٙ???5?nq]M??VM???`Q?>`???'t#F????A?'?e_??1??cɛ?ڋYC??kaF??<-Yx?O85??8G?\??F?v/zl%????0?3M=L? \??T???!)?2??T?6/????1t??I???s???l?ǧ0?k?{KD???????K?Ѓ?w?T?&?x?}S[Ǿ?(???<?b%?Cc?M
??\Gˍ??l?>?7C?xP*?W%E??|??3??M???Ӑ??E?g??}7??Z/? ??g??k??E????x????E      ^      x?????? ? ?      _      x?????? ? ?      `      x?????? ? ?      a   .   x??022012??H-J???KUH?)?H?? [ ??RK?b???? kW?      b   ?   x?}̱
?0??9}
GN?.?K:j+T??K.?E????\???o`F??H?F???4?b9^?@+G?^??4eG5Q?1??^@*?`R?V??j?2?~??6ݰ????GM????V3Yn?s	 ?2X?????Ee????]7M???.?      c   `   x?]̩?0P?*f???hP
0L?uD?1?sl0??a?7?ڣ??:mm??:?WE???Bxj?꥖Bw???(G'?v*#???Q????t?
z?D?d?"\      d   -   x???w?561?L????LM4?C?t59K?"???@?=... ϧ?      e   ?   x???M
?0@?????2?d?f9M??-mD7?.??????q!x???`??6 ;????5?v`,??????Btl??-?TW???J)?Y?e)*??1??(?C7Bp?+??)???Uz?c?*?q?^"#s?GgA,?78????v?<`~?O??$???f%???w??*????G?      f   ?   x?uϻj1??z?.c?*iʰ6?b??2?^???B?7????,"??ٲ?????RJ1R.??	????hq?۝;يFA?(??U?q?}^??<??@iy????(=9*#u??2??ќ?悥?zl??op????@????G?q???.?wE?h[ن$?يJ????x?oo?t?D??!??ܓC?     