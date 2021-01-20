/* requete pour découper des polygones selon une largeur et une hauteur prédéfinie pour la ralisation d'un atlas
Le découpage s'effectue en horizontal puis sur le même principe en vertical.
Pour le découpage en horizontal, on crée en premier un groupe de bandes horizontales jointives d'une largeur supérieure 
à celle du plus large polygones. Puis pour chaque commune on détermine le nombre de bandes qui servira à la découpe, puis à partir
du groupe modèle on sélectionne pour chaque commune le nombre de bandes et on translate ce groupe de bande sur la commune concernée
en alignant le centre la commune avec le centre du groupe. On fait alors l'intersection des géométries. 
Le découpage vertical s'effectue avec la même logique sur les ojets précédément obtenues.
Pour accélérer le traitement on ne fait l'opération que sur les objets devant être découpés.
Sans doute possibilité d'améliorer le temps de traitement en créant autant de type de groupe de bande et de déplacer ces types au lieu
de créer un groupe par commune puis de les déplacer*/
 
drop materialized view if exists mon_schema.ma_grille;
create materialized view mon_schema.ma_grille as
with 

    largeur_carte as (select 227 as l),--largeur de la fenêtre carte en mm
    hauteur_carte as (select 173.125 as h),--hauteur de la fenêtre carte en mm
    recouvrement_carte as (select 10 as r),--recouvrement minimal entre planche en mm
    echelle_carte as (select 25000 as e),--echelle de sortie des cartes
    
    
    /*on filtre les objets qu'on souhaite intégrer à l'atlas et on rajoute des informations*/
    perimetre_atlas as (
        select 
            insee_com as id_perimetre,
            st_xmax(geom) as xmax,
            st_xmin(geom) as xmin,
            st_ymax(geom) as ymax,
            st_ymin(geom) as ymin,
            geom 
        from "adminExpress".commune 
        where insee_reg='28'
    ),
    
    /*on calcul la largeur dans le monde réelle de la carte*/
    largeur AS (
        select ((a.l - c.r) * b.e/1000) AS l 
        from largeur_carte a 
            cross join echelle_carte b
            cross join recouvrement_carte c
    ),
    
    /*on calcul la hauteur dans le monde réelle de la carte*/
    hauteur AS (
        select ((a.h - c.r) * b.e/1000) AS h
        from hauteur_carte a 
            cross join echelle_carte b
            cross join recouvrement_carte c
    ),

    /*on repère les polygones devant être découpés en horizontal ou en vertical i.e. ceeux qui sont plus larges que la largeur définie pour la carte ou ceux qui sont plus hauts*/
    extrait_perim as (
        select 
            *
        from perimetre_atlas as a
            cross join hauteur as b
            cross join largeur as c
        where st_ymax(geom)-st_ymin(geom) > b.h or st_xmax(geom)-st_xmin(geom) > c.l   
    ),
  
  /* recherche du nombre de bandes horizontales maximum à créer pour le groupe modèles */
     max_bande_h as (
        select 
            (max(trunc((ymax-ymin)/b.h)+1))::integer max_horizontal --attention théoriquement il faudrait vérifier que (ymax-ymin)/2 ne serait pas un entier
        from extrait_perim a
            cross join hauteur b
    ),
  
  /* calcul de la largeur des bandes modèles à créer sur la base du polygone le plus large*/
    max_largeur as (select max(xmax-xmin+10) as lmax from extrait_perim ),
  
  /*création de la première bande horizontal du groupe modèle*/
    bande_horizontale as (
        select 
      st_setsrid(
        st_makepolygon(
          st_makeline(
            array[
              st_makepoint(0,0),--1er sommet à l'origine
              st_makepoint(a.lmax,0),--2e sommet décalé en x de la largeur max calculée précédément
              st_makepoint(a.lmax,b.h),--3e sommet décalé en y de la hauteur prédéfinie
              st_makepoint(0,b.h),--4e sommet pour revenir sur l'axe des y
              st_makepoint(0,0)--dernier sommet pour fermer la ligne
            ]
          )
        ),2154)::geometry('polygon',2154) as geom
    from max_largeur a 
      cross join hauteur b
    ),
  
  /*création du groupe de bande par translation de la première.*/
    groupe_bande_horizontale as (
        select
                a.gid,
                st_translate(b.geom,0,(a.gid-1)*c.h)::geometry('polygon',2154) geom
        from (select generate_series(1,(select * from max_bande_h)) as gid) a --génére une série de 1 au nb max de bandes calculé précédément
            cross join bande_horizontale b
            cross join hauteur c
    ),
  
  /*pour chaque commune à découper, calcul du nombre de bande nécessaire pour la découpe*/
    nb_bandes_h_commune as (
        select 
            a.id_perimetre,
            (trunc((ymax-ymin)/b.h)+1)::integer as nb_bande_com, --théoriquement il faudrait vérifier que (ymax-ymin)/hauteur ne soit pas un entier
            a.geom
        from extrait_perim as a
            cross join hauteur as b
    ),
  
  /*on crée pour chaque commune à découper un groupe de bandes du nombre de bandes calculé précédément*/
    bandes_h_com as (
        select 
            a.id_perimetre,
            b.gid as gid_bande,
            b.geom
        from nb_bandes_h_commune as a
            join groupe_bande_horizontale b on b.gid <= a.nb_bande_com --possible car les identifiants des bandes du groupe modèles sont dans l'ordre de bas en haut
    ),
  
  /*on calcul le point central du groupe de bandes de chaque commune*/
    centre_bandes_h_com as (
        select 
            id_perimetre,
            st_centroid(st_union(geom))::geometry('point',2154) as geom
        from bandes_h_com
        group by id_perimetre
    ),
  
  /*on translate le groupe de bandes de chaque commune pour que le centre du groupe corresponde au centre de chaque commune.
  Attention, les objets communes étant complexe il est préférable de ne pas utiliser le centroide mais de faire un calcul
  direct en fonction des coordonnées extrèmes de l'objet*/
    bandes_h_com_translate as (
        select 
            a.id_perimetre,
            a.gid_bande,
            st_translate(a.geom,((b.xmax+b.xmin)/2)-st_x(c.geom),((b.ymax+b.ymin)/2)-st_y(c.geom))::geometry('polygon',2154) geom --permet de translater l'objet
        from bandes_h_com as a 
            join extrait_perim as b using (id_perimetre)
            join centre_bandes_h_com as c using (id_perimetre)
    ),
  
  /*decoupage de polygone avec les bandes translatées*/
    decoupe_com as (
        select
            a.id_perimetre,
            b.gid_bande as gid_bande_h,
            st_intersection(a.geom,b.geom) as geom 
        from extrait_perim as a
            join bandes_h_com_translate as b using (id_perimetre)
    ),
  
  /*on fait la même chose pour le découpage vertical mais en partant des polygones issus du découpage horizontal*/
    extrait_decoupe_com as (
        select
            a.id_perimetre,
            a.gid_bande_h,
            st_xmax(geom) as xmax,
            st_xmin(geom) as xmin,
            st_ymax(geom) as ymax,
            st_ymin(geom) as ymin,
            a.geom
        from decoupe_com as a
            cross join largeur as b
        where st_xmax(geom)-st_xmin(geom) > b.l
    ) ,
    max_bande_v as (
        select 
            (max(trunc((xmax-xmin)/b.l)+1))::integer max_horizontal
        from extrait_perim a
            cross join largeur b
    ),
    bande_verticale as (
        select st_setsrid(st_makepolygon(st_makeline(array[st_makepoint(0,0),st_makepoint(a.l,0),st_makepoint(a.l,b.h+100),st_makepoint(0,b.h+100),st_makepoint(0,0)])),2154)::geometry('polygon',2154) as geom
            from largeur a 
                cross join hauteur b
    ),
     groupe_bande_verticale as (
        select
                a.gid,
                st_translate(b.geom,(a.gid-1)*c.l,0)::geometry('polygon',2154) geom
        from (select generate_series(1,(select * from max_bande_v)) as gid) a
            cross join bande_verticale b
            cross join largeur c
    ),
    nb_bandes_v_commune as (
        select 
            a.id_perimetre,
            a.gid_bande_h,
            (trunc((xmax-xmin)/b.l)+1)::integer as nb_bande_com,
            a.geom
        from extrait_decoupe_com as a
            cross join largeur as b
    ),
    bandes_v_com as (
        select 
            a.id_perimetre,
            a.gid_bande_h,
            b.gid as gid_bande_v,
            b.geom
        from nb_bandes_v_commune as a
            join groupe_bande_verticale b on b.gid <= a.nb_bande_com
    ),
    centre_bandes_v_com as (
        select 
            id_perimetre,
            gid_bande_h,
            st_centroid(st_union(geom))::geometry('point',2154) as geom
        from bandes_v_com
        group by id_perimetre, gid_bande_h
    ),
    bandes_v_com_translate as (
        select 
            a.id_perimetre,
            a.gid_bande_h,
            a.gid_bande_v,
            st_translate(a.geom,((b.xmax+b.xmin)/2)-st_x(c.geom),((b.ymax+b.ymin)/2)-st_y(c.geom))::geometry('polygon',2154) geom
        from bandes_v_com as a 
            join extrait_decoupe_com  as b using (id_perimetre, gid_bande_h)
            join centre_bandes_v_com as c using (id_perimetre, gid_bande_h)
    ),
    decoupe_v_com as (
        select
            a.id_perimetre,
            b.gid_bande_h,
            b.gid_bande_v,
            st_intersection(a.geom,b.geom) geom
        from extrait_decoupe_com as a
            join bandes_v_com_translate as b using (id_perimetre, gid_bande_h )
    ),
  
  /*on regroupe tout en fonction de chaque type*/
    regroupe_morceau as (
    /*communes ne nécessitant pas de découpage*/
        select
          a.id_perimetre,
          1::integer as gid_bande_h,
          1::integer as gid_bande_v,
          a.geom
        from perimetre_atlas as a
          cross join hauteur as b
          cross join largeur as c
        where (st_ymax(geom)-st_ymin(geom) <= b.h and st_xmax(geom)-st_xmin(geom) <= c.l)
    /*morceau de commune découpé horizontalement ne nécessitant pas de découpage vertical*/
        union
        select
          a.id_perimetre,
          a.gid_bande_h,
          1::integer as gid_bande_v,
          a.geom
        from decoupe_com as a
          cross join largeur as b
        where st_xmax(geom)-st_xmin(geom) <= b.l
        union
    /*morceau de commune ayant nécessité un découpage vertical*/
        select
            *
        from decoupe_v_com
    )
    
/*requete final permetant une numérotation unique de chaque ligne*/
select 
  row_number() over() gid,
  id_perimetre,
  row_number() over (
    partition by id_perimetre
    order by id_perimetre,gid_bande_h, gid_bande_v) as num,
  st_multi(case
        when st_geometrytype(geom) ilike '%collect%' then st_multi(st_collectionextract(geom, 3))
        else geom
    end)::geometry(MultiPolygon,2154) AS geom
  from regroupe_morceau order by id_perimetre,gid_bande_h, gid_bande_v

  